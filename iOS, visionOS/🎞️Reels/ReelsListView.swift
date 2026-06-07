import AVKit
import CoreImage
import Photos
import PhotosUI
import SwiftUI
import UIKit
import Vision

struct ReelsListView: View {
    var body: some View {
        ReelplayRootView()
    }
}

struct ReelplayRootView: View {
    @EnvironmentObject var app: 📱AppModel
    @AppStorage("reelplay.socialProfileID") private var socialProfileID = ""
    @AppStorage("reelplay.socialHandle") private var socialHandle = ""
    @AppStorage("reelplay.lastOpenedReelID") private var lastOpenedReelID = ""
    @State private var reels: [ReelItem] = []
    @State private var socialSummary: ReelSocialSummary = .empty
    @State private var socialProfile: ReelSocialProfile?
    @State private var discoveredReels: [ReelItem] = []
    @State private var discoveredNiches: [String] = []
    @State private var shareInbox: [ReelFriendShare] = []
    @State private var hasLoadedDiscovery = false
    @State private var hasLoadedSocialState = false
    @State private var selectedTab: ReelplayTab = .home
    @State private var selectedReel: ReelItem?
    @State private var searchText = ""
    @State private var importText = ""
    @State private var selectedHomeCollectionID: String?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var isProcessingPendingOCR = false
    @State private var activeOCRReelIDs = Set<UUID>()
    @State private var importStageIndex = 0
    @State private var importElapsedSeconds = 0
    @State private var importingURL: URL?
    @State private var isPreparingSelectedReel = false
    @State private var selectedReelStageIndex = 0
    @State private var selectedReelElapsedSeconds = 0
    @State private var preparingReelTitle: String?
    @State private var errorMessage: String?

    private let importStages = [
        "Reading reel",
        "Transcribing audio",
        "Finding key moments",
        "Building microreels",
    ]

    private let selectedReelStages = [
        "Preparing video",
        "Reading on-screen text",
        "Improving timestamps",
        "Starting microreel",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ReelplayTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    self.content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ReelplayTabBar(selectedTab: self.$selectedTab)
                }

                if self.isImporting {
                    ImportReelOverlay(
                        title: "Importing",
                        headline: "Processing your reel...",
                        subheadline: "This usually takes 15-30 seconds.",
                        footer: "You will be notified when it is ready.",
                        sourceURL: self.importingURL,
                        stages: self.importStages,
                        activeStageIndex: self.importStageIndex,
                        progress: self.progress(
                            activeStageIndex: self.importStageIndex,
                            stageCount: self.importStages.count,
                            elapsedSeconds: self.importElapsedSeconds
                        ),
                        encouragement: self.encouragement(for: self.importElapsedSeconds)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if self.isPreparingSelectedReel {
                    ImportReelOverlay(
                        title: "Loading Reel",
                        headline: "Preparing your microreel...",
                        subheadline: "Reading the video and improving key moments.",
                        footer: "Opening as soon as it is ready.",
                        sourceURL: nil,
                        stages: self.selectedReelStages,
                        activeStageIndex: self.selectedReelStageIndex,
                        progress: self.progress(
                            activeStageIndex: self.selectedReelStageIndex,
                            stageCount: self.selectedReelStages.count,
                            elapsedSeconds: self.selectedReelElapsedSeconds
                        ),
                        encouragement: self.encouragement(for: self.selectedReelElapsedSeconds)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: self.$selectedReel) { reel in
                ReelDetailView(
                    reel: reel,
                    isBookmarked: self.socialSummary.bookmarkIDs.contains(reel.id),
                    isPubliclyShared: self.socialSummary.publicReelIDs.contains(reel.id),
                    onToggleBookmark: { await self.toggleBookmark(for: reel) },
                    onTogglePublicShare: { await self.togglePublicShare(for: reel) },
                    onShareWithFriend: { handle in await self.share(reel, with: handle) },
                    onDelete: { await self.deleteReel($0) }
                )
            }
        }
        .task {
            await self.bootstrapSocialProfileIfNeeded()
            await self.loadReels()
        }
        .task(id: self.isImporting) {
            guard self.isImporting else { return }
            await self.animateImportStages()
        }
        .onChange(of: self.app.sharedReelURL) { _, url in
            guard let url else { return }
            self.importText = url.absoluteString
            self.selectedTab = .add
            Task { await self.importURL(url) }
        }
        .onChange(of: self.selectedTab) { _, tab in
            Task { await self.loadDataIfNeeded(for: tab) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.selectedTab {
            case .home:
                ReelplayHomeScreen(
                    reels: self.reels,
                    collections: self.collections,
                    continueReel: self.continuePlayingReel,
                    isLoading: self.isLoading,
                    errorMessage: self.errorMessage,
                    selectedCollectionID: self.$selectedHomeCollectionID,
                    onSelectReel: { self.prepareAndOpenReel($0) },
                    onSelectCollection: { collection in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            self.selectedHomeCollectionID = self.selectedHomeCollectionID == collection.id ? nil : collection.id
                        }
                    },
                    onRefresh: { await self.loadReels() },
                    onImport: { self.selectedTab = .add },
                    onDelete: { await self.deleteReel($0) },
                    searchText: self.$searchText
                )
            case .search:
                ReelplaySearchScreen(
                    reels: self.reels,
                    socialReels: self.discoveredReels,
                    niches: self.discoveredNiches,
                    searchText: self.$searchText,
                    onSelectReel: { self.prepareAndOpenReel($0) }
                )
            case .add:
                ReelplayImportScreen(
                    importText: self.$importText,
                    isImporting: self.isImporting,
                    errorMessage: self.errorMessage,
                    onImport: { Task { await self.importCurrentURL() } },
                    onGalleryImport: { localURL in await self.importGalleryVideo(localURL: localURL) }
                )
            case .collections:
                ReelplayCollectionsScreen(
                    collections: self.collections,
                    socialCollections: self.socialSummary.collections,
                    inbox: self.shareInbox,
                    reels: self.reels,
                    onShareCollection: { collection, handle in await self.share(collection, with: handle) },
                    onCreateCollection: { name, reelIDs, isPublic in await self.createCollection(name: name, reelIDs: reelIDs, isPublic: isPublic) },
                    onSelectReel: { self.prepareAndOpenReel($0) }
                )
            case .profile:
                ReelplayProfileScreen(
                    reels: self.reels,
                    profile: self.socialProfile,
                    handle: self.socialHandle,
                    bookmarkedReelIDs: self.socialSummary.bookmarkIDs,
                    publicReelIDs: self.socialSummary.publicReelIDs,
                    collections: self.collections,
                    friends: self.socialSummary.friends,
                    incomingFriendRequests: self.socialSummary.incomingFriendRequests,
                    outgoingFriendRequests: self.socialSummary.outgoingFriendRequests,
                    inbox: self.shareInbox,
                    onSaveHandle: { await self.saveHandle($0) },
                    onAddFriend: { await self.addFriend(handle: $0) },
                    onRespondToFriendRequest: { friendship, accept in await self.respond(to: friendship, accept: accept) },
                    onPublishSavedList: { await self.publishSavedList() },
                    onSelectReel: { self.prepareAndOpenReel($0) }
                )
        }
    }

    private var collections: [ReelCollection] {
        let groups = Dictionary(grouping: self.reels, by: ReelCollection.categoryName(for:))
        return groups
            .map { name, reels in
                ReelCollection(name: name, count: reels.count)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name < rhs.name
            }
    }

    private var continuePlayingReel: ReelItem? {
        if let id = UUID(uuidString: self.lastOpenedReelID),
           let reel = self.reels.first(where: { $0.id == id }) {
            return reel
        }

        return self.reels.first
    }

    private func loadReels() async {
        do {
            self.errorMessage = nil
            self.isLoading = true
            let service = try ReelService()
            guard let profileID = self.currentSocialProfileID else {
                throw ReelService.ServiceError.backend("Missing Reelplay profile.")
            }
            self.reels = try await service.listProfileLibrary(profileID: profileID, limit: 30)
            if let selectedReel {
                self.selectedReel = self.reels.first { $0.id == selectedReel.id } ?? selectedReel
            }
            Task { await self.processPendingOCRReelsIfNeeded() }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
    }

    private func deleteReel(_ reel: ReelItem) async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            self.errorMessage = nil
            try await ReelService().removeFromLibrary(id: reel.id, profileID: profileID)
            self.reels.removeAll { $0.id == reel.id }
            if self.selectedReel?.id == reel.id {
                self.selectedReel = nil
            }
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private var currentSocialProfileID: UUID? {
        UUID(uuidString: self.socialProfileID)
    }

    private var defaultSocialProfileID: UUID {
        UIDevice.current.identifierForVendor ?? UUID()
    }

    private func bootstrapSocialProfileIfNeeded() async {
        do {
            let profileID: UUID
            if let existingID = UUID(uuidString: self.socialProfileID) {
                profileID = existingID
            } else {
                profileID = self.defaultSocialProfileID
                self.socialProfileID = profileID.uuidString
            }

            if self.socialHandle.isEmpty {
                self.socialHandle = "user-\(profileID.uuidString.prefix(8).lowercased())"
            }

            self.socialProfile = try await ReelService().upsertSocialProfile(
                profileID: profileID,
                handle: self.socialHandle,
                displayName: "Reelplay User"
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func loadDataIfNeeded(for tab: ReelplayTab) async {
        switch tab {
            case .search:
                if !self.hasLoadedDiscovery {
                    await self.loadDiscovery()
                }
            case .collections, .profile:
                if !self.hasLoadedSocialState {
                    await self.loadSocialState()
                }
            case .home, .add:
                break
        }
    }

    private func loadSocialState() async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            let service = try ReelService()
            self.socialSummary = try await service.socialSummary(profileID: profileID)
            self.shareInbox = try await service.shareInbox(profileID: profileID).shares
            self.hasLoadedSocialState = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func loadDiscovery() async {
        do {
            let discovery = try await ReelService().discoverSocialReels(limit: 30)
            self.discoveredReels = discovery.reels
            self.discoveredNiches = discovery.niches
            self.hasLoadedDiscovery = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func toggleBookmark(for reel: ReelItem) async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            let isBookmarked = !self.socialSummary.bookmarkIDs.contains(reel.id)
            self.socialSummary = try await ReelService().setBookmark(
                profileID: profileID,
                reelID: reel.id,
                isBookmarked: isBookmarked
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func togglePublicShare(for reel: ReelItem) async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            let isPublic = !self.socialSummary.publicReelIDs.contains(reel.id)
            self.socialSummary = try await ReelService().setPublicShare(
                profileID: profileID,
                reelID: reel.id,
                isPublic: isPublic,
                nicheTags: [ReelCollection.categoryName(for: reel)]
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func share(_ reel: ReelItem, with handle: String) async {
        guard let profileID = self.currentSocialProfileID else { return }
        let cleanedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHandle.isEmpty else { return }

        do {
            self.socialSummary = try await ReelService().shareWithFriend(
                profileID: profileID,
                reelID: reel.id,
                receiverHandle: cleanedHandle,
                message: nil
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func share(_ collection: ReelSocialCollection, with handle: String) async {
        guard let profileID = self.currentSocialProfileID else { return }
        let cleanedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHandle.isEmpty else { return }

        do {
            self.socialSummary = try await ReelService().shareCollectionWithFriend(
                profileID: profileID,
                collectionID: collection.id,
                receiverHandle: cleanedHandle,
                message: nil
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func saveHandle(_ handle: String) async {
        guard let profileID = self.currentSocialProfileID else { return }
        let cleanedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHandle.isEmpty else { return }

        do {
            let profile = try await ReelService().upsertSocialProfile(
                profileID: profileID,
                handle: cleanedHandle,
                displayName: "Reelplay User"
            )
            self.socialProfile = profile
            self.socialHandle = profile.handle
            self.hasLoadedSocialState = false
            await self.loadSocialState()
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func addFriend(handle: String) async {
        guard let profileID = self.currentSocialProfileID else { return }
        let cleanedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHandle.isEmpty else { return }

        do {
            let state = try await ReelService().requestFriend(profileID: profileID, receiverHandle: cleanedHandle)
            self.apply(friendState: state)
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func respond(to friendship: ReelFriendship, accept: Bool) async {
        guard let profileID = self.currentSocialProfileID else { return }

        do {
            let state = try await ReelService().respondToFriendRequest(
                profileID: profileID,
                friendshipID: friendship.id,
                accept: accept
            )
            self.apply(friendState: state)
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func apply(friendState: ReelFriendState) {
        self.socialSummary = ReelSocialSummary(
            bookmarkIDs: self.socialSummary.bookmarkIDs,
            publicReelIDs: self.socialSummary.publicReelIDs,
            publicShares: self.socialSummary.publicShares,
            collections: self.socialSummary.collections,
            friendShares: self.socialSummary.friendShares,
            friendships: friendState.friendships,
            friends: friendState.friends,
            incomingFriendRequests: friendState.incomingFriendRequests,
            outgoingFriendRequests: friendState.outgoingFriendRequests,
            niches: self.socialSummary.niches,
            popularReels: self.socialSummary.popularReels
        )
    }

    private func importGalleryVideo(localURL: URL) async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            self.errorMessage = nil
            self.isImporting = true

            let asset = AVURLAsset(url: localURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = Int(duration.seconds)
            let title = localURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            let fileName = "\(UUID().uuidString).mp4"
            let storageURL = try await ReelService().uploadVideoToStorage(localURL: localURL, fileName: fileName)

            var reel = try await ReelService().importGalleryReel(
                videoURL: storageURL,
                title: title,
                durationSeconds: durationSeconds,
                profileID: profileID
            )
            self.reels.insert(reel, at: 0)
            self.selectedTab = .home

            reel = await self.processOCR(for: reel)
            if let idx = self.reels.firstIndex(where: { $0.id == reel.id }) {
                self.reels[idx] = reel
            }

            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
        self.isImporting = false
    }

    private func createCollection(name: String, reelIDs: [UUID], isPublic: Bool) async {
        guard let profileID = self.currentSocialProfileID else { return }
        do {
            self.socialSummary = try await ReelService().createCollection(
                profileID: profileID,
                name: name,
                reelIDs: reelIDs,
                isPublic: isPublic
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func publishSavedList() async {
        guard let profileID = self.currentSocialProfileID else { return }
        let reelIDs = self.socialSummary.bookmarkIDs.isEmpty ? self.reels.prefix(12).map(\.id) : self.socialSummary.bookmarkIDs
        guard !reelIDs.isEmpty else { return }

        do {
            self.socialSummary = try await ReelService().createCollection(
                profileID: profileID,
                name: "Saved Reelplays",
                reelIDs: Array(reelIDs),
                isPublic: true
            )
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
    }

    private func importCurrentURL() async {
        let text = self.importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), 📱AppModel.isSupportedReelURL(url) else {
            self.errorMessage = "Paste a valid Instagram or TikTok reel link."
            💥Feedback.error()
            return
        }

        await MainActor.run {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        await self.importURL(url)
    }

    private func importURL(_ url: URL) async {
        guard let profileID = self.currentSocialProfileID else {
            self.errorMessage = "Missing Reelplay profile."
            💥Feedback.error()
            return
        }

        do {
            self.errorMessage = nil
            self.isImporting = true
            self.importingURL = url
            self.importStageIndex = 0
            self.importElapsedSeconds = 0

            var reel = try await ReelService().importReel(url: url, profileID: profileID)
            self.reels.removeAll { $0.id == reel.id }
            self.reels.insert(reel, at: 0)

            if reel.needsOCRProcessing {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.importStageIndex = max(self.importStageIndex, 2)
                }
                reel = await self.processOCRWithTimeout(for: reel)
                self.reels.removeAll { $0.id == reel.id }
                self.reels.insert(reel, at: 0)
            }

            self.importText = ""
            self.app.sharedReelURL = nil
            self.prepareAndOpenReel(reel)
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }

        self.isImporting = false
        self.importElapsedSeconds = 0
        self.importingURL = nil
    }

    private func animateImportStages() async {
        while !Task.isCancelled && self.isImporting {
            try? await Task.sleep(for: .seconds(1))
            guard self.isImporting else { return }
            self.importElapsedSeconds += 1
            if self.importElapsedSeconds.isMultiple(of: 2) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.importStageIndex = min(self.importStageIndex + 1, self.importStages.count - 1)
                }
            }
        }
    }

    private func prepareAndOpenReel(_ reel: ReelItem) {
        guard !self.isPreparingSelectedReel else { return }
        self.lastOpenedReelID = reel.id.uuidString

        let needsProcessing = reel.needsOCRProcessing || !reel.isMicroreelReady

        if !needsProcessing {
            // Open immediately with current data, refresh silently in background
            self.selectedReel = reel
            Task {
                guard let fresh = try? await ReelService().reel(id: reel.id) else { return }
                await MainActor.run {
                    self.reels.removeAll { $0.id == fresh.id }
                    self.reels.insert(fresh, at: 0)
                    if self.selectedReel?.id == fresh.id {
                        self.selectedReel = fresh
                    }
                }
            }
            return
        }

        // Needs OCR or processing — show overlay
        self.preparingReelTitle = reel.title
        self.selectedReelStageIndex = 0
        self.selectedReelElapsedSeconds = 0
        self.isPreparingSelectedReel = true

        Task {
            let animationTask = Task { await self.animateSelectedReelStages() }
            let preparedReel = await self.latestPreparedReel(for: reel)
            animationTask.cancel()
            await MainActor.run {
                self.reels.removeAll { $0.id == preparedReel.id }
                self.reels.insert(preparedReel, at: 0)
                self.selectedReel = preparedReel
                self.isPreparingSelectedReel = false
                self.selectedReelElapsedSeconds = 0
                self.preparingReelTitle = nil
            }
        }
    }

    private func latestPreparedReel(for reel: ReelItem) async -> ReelItem {
        do {
            let latestReel = try await ReelService().reel(id: reel.id)
            if latestReel.needsOCRProcessing || !latestReel.isMicroreelReady {
                return await self.processOCRWithTimeout(for: latestReel)
            }

            return latestReel
        } catch {
            if reel.needsOCRProcessing || !reel.isMicroreelReady {
                return await self.processOCRWithTimeout(for: reel)
            }

            return reel
        }
    }

    private func processPendingOCRReelsIfNeeded() async {
        guard !self.isProcessingPendingOCR else { return }
        let candidates = self.reels
            .filter(\.needsOCRProcessing)
            .prefix(3)

        guard !candidates.isEmpty else { return }
        self.isProcessingPendingOCR = true
        defer { self.isProcessingPendingOCR = false }

        for reel in candidates {
            let updatedReel = await self.processOCR(for: reel)
            self.reels.removeAll { $0.id == updatedReel.id }
            self.reels.insert(updatedReel, at: 0)
        }
    }

    private func processOCRWithTimeout(for reel: ReelItem) async -> ReelItem {
        await withTaskGroup(of: ReelItem.self) { group in
            group.addTask {
                await self.processOCR(for: reel)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(90))
                return reel
            }

            let result = await group.next() ?? reel
            group.cancelAll()
            return result
        }
    }

    private func animateSelectedReelStages() async {
        while !Task.isCancelled && self.isPreparingSelectedReel {
            try? await Task.sleep(for: .seconds(1))
            guard self.isPreparingSelectedReel else { return }
            self.selectedReelElapsedSeconds += 1
            if self.selectedReelElapsedSeconds.isMultiple(of: 2) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.selectedReelStageIndex = min(self.selectedReelStageIndex + 1, self.selectedReelStages.count - 1)
                }
            }
        }
    }

    private func progress(activeStageIndex: Int, stageCount: Int, elapsedSeconds: Int) -> Double {
        guard stageCount > 0 else { return 0.08 }
        let boundedStage = min(max(activeStageIndex, 0), stageCount - 1)
        let stageWidth = 1.0 / Double(stageCount)
        let stageProgress = (Double(boundedStage) * stageWidth) + (stageWidth * 0.56)
        let elapsedNudge = min(0.16, Double(elapsedSeconds) / 120)
        return min(0.96, max(0.08, stageProgress + elapsedNudge))
    }

    private func encouragement(for elapsedSeconds: Int) -> String? {
        guard elapsedSeconds >= 5 else { return nil }
        let messages = [
            "Getting there. We are lining up the best moments.",
            "Reading the details so the steps feel precise.",
            "Tightening the timestamps now.",
            "Finding the moments worth replaying.",
            "This reel has a little more to unpack.",
            "Sorting the clips into clean steps.",
            "Checking the on-screen text one more time.",
            "Building the replayable steps.",
            "Almost ready. Keeping the microreel smooth.",
            "Final pass now. Thanks for sticking with it.",
            "Still working. Longer reels can take a little extra time.",
            "Finishing the timeline so playback lands cleanly.",
            "One more moment. We are saving the best breakdown.",
        ]
        let index = min((elapsedSeconds - 5) / 5, messages.count - 1)
        return messages[index]
    }

    private func processOCR(for reel: ReelItem) async -> ReelItem {
        guard !self.activeOCRReelIDs.contains(reel.id) else { return reel }
        await MainActor.run { self.activeOCRReelIDs.insert(reel.id) }
        defer { Task { @MainActor in self.activeOCRReelIDs.remove(reel.id) } }

        let mediaItems = reel.mediaItems ?? []
        if reel.videoURL == nil && !mediaItems.isEmpty {
            return await processSlideOCR(for: reel, mediaItems: mediaItems)
        }

        guard let videoURL = reel.videoURL else { return reel }

        do {
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.selectedReelStageIndex = max(self.selectedReelStageIndex, 1)
                }
            }
            let entries = try await ReelOCRProcessor().recognizeText(
                in: videoURL,
                durationSeconds: reel.durationSeconds
            )
            guard !entries.isEmpty else {
                return (try? await ReelService().submitOCR(reelID: reel.id, entries: [])) ?? reel
            }

            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.selectedReelStageIndex = max(self.selectedReelStageIndex, 2)
                }
            }
            let updatedReel = try await ReelService().submitOCR(reelID: reel.id, entries: entries)
            await MainActor.run {
                self.reels.removeAll { $0.id == updatedReel.id }
                self.reels.insert(updatedReel, at: 0)
            }
            return updatedReel
        } catch {
            print("Reel OCR failed: \(error.localizedDescription)")
            return reel
        }
    }

    private func processSlideOCR(for reel: ReelItem, mediaItems: [ReelMediaItem]) async -> ReelItem {
        do {
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.selectedReelStageIndex = max(self.selectedReelStageIndex, 1)
                }
            }
            let entries = try await ReelOCRProcessor().recognizeTextInSlides(mediaItems)
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.selectedReelStageIndex = max(self.selectedReelStageIndex, 2)
                }
            }
            let updatedReel = try await ReelService().submitOCR(reelID: reel.id, entries: entries)
            await MainActor.run {
                self.reels.removeAll { $0.id == updatedReel.id }
                self.reels.insert(updatedReel, at: 0)
            }
            return updatedReel
        } catch {
            print("Slideshow OCR failed: \(error.localizedDescription)")
            return reel
        }
    }
}

private enum ReelplayTab: CaseIterable {
    case home
    case search
    case add
    case collections
    case profile

    var title: String {
        switch self {
            case .home: "Home"
            case .search: "Search"
            case .add: "Import"
            case .collections: "Collections"
            case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
            case .home: "house"
            case .search: "magnifyingglass"
            case .add: "plus"
            case .collections: "folder"
            case .profile: "person"
        }
    }
}

private enum ReelplayTheme {
    static let black = Color(hex: 0x0F0F10)
    static let charcoal = Color(hex: 0x1C1C1E)
    static let background = Color(hex: 0xF7F6F2)
    static let surface = Color(hex: 0xFFFFFF)
    static let softSurface = Color(hex: 0xE8E5DF)
    static let accent = Color(hex: 0xD4C7A7)
    static let mutedText = Color.black.opacity(0.54)
    static let divider = Color.black.opacity(0.08)
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

private struct ReelplayHomeScreen: View {
    private let horizontalInset: CGFloat = 20

    let reels: [ReelItem]
    let collections: [ReelCollection]
    let continueReel: ReelItem?
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedCollectionID: String?
    let onSelectReel: (ReelItem) -> Void
    let onSelectCollection: (ReelCollection) -> Void
    let onRefresh: () async -> Void
    let onImport: () -> Void
    let onDelete: (ReelItem) async -> Void
    @Binding var searchText: String
    @State private var menuReel: ReelItem?

    private var selectedCollection: ReelCollection? {
        self.collections.first { $0.id == self.selectedCollectionID }
    }

    private var selectedCollectionReels: [ReelItem] {
        guard let selectedCollection else { return [] }
        return self.reels.filter { ReelCollection.categoryName(for: $0) == selectedCollection.name }
    }

    private var isInitialLibraryEmpty: Bool {
        self.reels.isEmpty && self.collections.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        Text("Reelplay")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)

                        Spacer()

                        Button {
                            Task { await self.onRefresh() }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(ReelplayTheme.black)
                                    .frame(width: 58, height: 58)
                                    .background(ReelplayTheme.surface)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                                Circle()
                                    .fill(ReelplayTheme.accent)
                                    .frame(width: 10, height: 10)
                                    .offset(x: -8, y: 10)
                            }
                        }
                        .disabled(self.isLoading)
                    }
                    .padding(.top, 8)

                    HomeHeroImportCard(featuredReel: self.reels.first, onImport: self.onImport)

                    HomeSearchField(text: self.$searchText)

                    if self.isInitialLibraryEmpty {
                        HomeInitialLibraryState(
                            isLoading: self.isLoading,
                            maxWidth: max(0, proxy.size.width - (self.horizontalInset * 2)),
                            onImport: self.onImport
                        )
                    } else {
                        if let continueReel {
                            VStack(alignment: .leading, spacing: 12) {
                                HomeSectionHeader(title: "Continue Playing", actionTitle: "See all")

                                Button {
                                    self.onSelectReel(continueReel)
                                } label: {
                                    ContinuePlayingCard(reel: continueReel, onMenuTap: {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            self.menuReel = continueReel
                                        }
                                    })
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !self.collections.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HomeSectionHeader(title: "Collections", actionTitle: "See all")

                                ScrollView(.horizontal) {
                                    HStack(spacing: 12) {
                                        ForEach(self.collections.prefix(8)) { collection in
                                            Button {
                                                self.onSelectCollection(collection)
                                            } label: {
                                                HomeCollectionCard(
                                                    collection: collection,
                                                    isSelected: self.selectedCollectionID == collection.id
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }

                        if let selectedCollection {
                            VStack(alignment: .leading, spacing: 12) {
                                HomeSectionHeader(title: selectedCollection.name, actionTitle: "Clear")
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                            self.selectedCollectionID = nil
                                        }
                                    }

                                ForEach(self.selectedCollectionReels) { reel in
                                    Button {
                                        self.onSelectReel(reel)
                                    } label: {
                                        HomeRecentReelRow(reel: reel, onMenuTap: {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                self.menuReel = reel
                                            }
                                        })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !self.reels.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HomeSectionHeader(title: "Recently Added", actionTitle: "See all")

                                VStack(spacing: 10) {
                                    ForEach(self.reels.prefix(8)) { reel in
                                        Button {
                                            self.onSelectReel(reel)
                                        } label: {
                                            HomeRecentReelRow(reel: reel, onMenuTap: {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                    self.menuReel = reel
                                                }
                                            })
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, self.horizontalInset)
                .frame(width: proxy.size.width, alignment: .leading)
                .padding(.top, -22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await self.onRefresh()
            }
            .blur(radius: self.menuReel != nil ? 3 : 0)
            .animation(.easeInOut(duration: 0.2), value: self.menuReel != nil)

            if self.menuReel != nil {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            self.menuReel = nil
                        }
                    }
                    .transition(.opacity)
            }

            if let reel = self.menuReel {
                ReelActionMenu(
                    reel: reel,
                    onShare: {
                        self.menuReel = nil
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            self.menuReel = nil
                        }
                        Task { await self.onDelete(reel) }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            self.menuReel = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
            } // ZStack
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: self.menuReel?.id)
        }
    }
}

private struct ReelplayImportScreen: View {
    @Binding var importText: String
    let isImporting: Bool
    let errorMessage: String?
    let onImport: () -> Void
    let onGalleryImport: (URL) async -> Void
    @State private var selectedSource = "Instagram"
    @State private var galleryItem: PhotosPickerItem?
    @State private var isPickingGallery = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Add Reel")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .frame(maxWidth: .infinity)

                Text("Save any reel and turn it into\nstep-by-step guide.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    ForEach(Self.sources, id: \.name) { source in
                        Button {
                            self.selectedSource = source.name
                        } label: {
                            ImportSourceOption(
                                source: source,
                                isSelected: self.selectedSource == source.name
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    TextField(self.placeholder, text: self.$importText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline.weight(.medium))

                    #if os(iOS)
                    Button {
                        if let text = UIPasteboard.general.string {
                            self.importText = text
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ReelplayTheme.black)
                    }
                    #endif
                }
                .padding(.horizontal, 18)
                .frame(height: 64)
                .background(ReelplayTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelplayTheme.divider))
                .shadow(color: .black.opacity(0.05), radius: 14, y: 7)

                Button(action: self.onImport) {
                    HStack {
                        if self.isImporting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(self.isImporting ? "Importing Reel" : "Import Reel")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(ReelplayTheme.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(self.isImporting || self.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                HStack {
                    Rectangle()
                        .fill(ReelplayTheme.divider)
                        .frame(height: 1)
                    Text("or")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ReelplayTheme.mutedText)
                    Rectangle()
                        .fill(ReelplayTheme.divider)
                        .frame(height: 1)
                }

                PhotosPicker(
                    selection: self.$galleryItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 10) {
                        if self.isPickingGallery {
                            ProgressView().tint(ReelplayTheme.black)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Text(self.isPickingGallery ? "Processing video…" : "Upload from gallery")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(ReelplayTheme.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(ReelplayTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelplayTheme.divider))
                }
                .disabled(self.isImporting || self.isPickingGallery)
                .onChange(of: self.galleryItem) { _, item in
                    guard let item else { return }
                    self.isPickingGallery = true
                    Task {
                        defer { self.isPickingGallery = false; self.galleryItem = nil }
                        guard let movie = try? await item.loadTransferable(type: VideoTransferable.self) else { return }
                        await self.onGalleryImport(movie.url)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: 0x9B7A45))
                    Text("We will analyze the reel and break it down into easy steps.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ReelplayTheme.accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var placeholder: String {
        switch self.selectedSource {
            case "TikTok": return "Paste TikTok link here..."
            case "YouTube Shorts": return "Paste a link here..."
            default: return "Paste reel link here..."
        }
    }

    private static let sources = [
        ImportSource(name: "Instagram", symbol: "camera", color: Color(hex: 0xD96BA8)),
        ImportSource(name: "TikTok", symbol: "music.note", color: ReelplayTheme.black),
    ]
}

private struct ReelplayCollectionsScreen: View {
    let collections: [ReelCollection]
    let socialCollections: [ReelSocialCollection]
    let inbox: [ReelFriendShare]
    let reels: [ReelItem]
    let onShareCollection: (ReelSocialCollection, String) async -> Void
    let onCreateCollection: (String, [UUID], Bool) async -> Void
    let onSelectReel: (ReelItem) -> Void

    @State private var selectedTab = 0
    @State private var expandedCollectionID: String?
    @State private var showCreateSheet = false
    @Namespace private var tabNamespace

    private let tabs = ["My Collections", "Shared", "Public Lists"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("Collections")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ReelplayTheme.black)

                Spacer()

                Button {
                    self.showCreateSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(ReelplayTheme.black)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(ReelplayTheme.softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 16)

            // Animated tab bar
            HStack(spacing: 0) {
                ForEach(Array(self.tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            self.selectedTab = index
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(tab)
                                .font(.subheadline.weight(self.selectedTab == index ? .bold : .medium))
                                .foregroundStyle(self.selectedTab == index ? ReelplayTheme.black : ReelplayTheme.mutedText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .animation(.easeInOut(duration: 0.18), value: self.selectedTab)

                            ZStack {
                                Rectangle()
                                    .fill(ReelplayTheme.divider)
                                    .frame(height: 1.5)

                                if self.selectedTab == index {
                                    Rectangle()
                                        .fill(ReelplayTheme.black)
                                        .frame(height: 2.5)
                                        .matchedGeometryEffect(id: "tabUnderline", in: self.tabNamespace)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // Tab content
            TabView(selection: self.$selectedTab) {
                CollectionsMyTab(
                    collections: self.collections,
                    reels: self.reels,
                    expandedCollectionID: self.$expandedCollectionID,
                    onSelectReel: self.onSelectReel
                )
                .tag(0)

                CollectionsSharedTab(
                    inbox: self.inbox,
                    onSelectReel: self.onSelectReel
                )
                .tag(1)

                CollectionsPublicTab(
                    socialCollections: self.socialCollections,
                    onShareCollection: self.onShareCollection
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: self.selectedTab)
        }
        .sheet(isPresented: self.$showCreateSheet) {
            CreateCollectionSheet(
                reels: self.reels,
                onCreate: { name, reelIDs, isPublic in
                    await self.onCreateCollection(name, reelIDs, isPublic)
                }
            )
        }
    }
}

private struct CollectionsMyTab: View {
    let collections: [ReelCollection]
    let reels: [ReelItem]
    @Binding var expandedCollectionID: String?
    let onSelectReel: (ReelItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if self.collections.isEmpty {
                    CollectionsEmptyState(
                        symbol: "folder",
                        title: "No collections yet",
                        subtitle: "Import reels — they'll be auto-grouped by topic here."
                    )
                } else {
                    ForEach(self.collections) { collection in
                        let reelsInCollection = self.reels.filter { ReelCollection.categoryName(for: $0) == collection.name }
                        let isExpanded = self.expandedCollectionID == collection.id

                        VStack(spacing: 0) {
                            CollectionLibraryCard(
                                collection: collection,
                                reels: reelsInCollection,
                                isSelected: isExpanded
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    self.expandedCollectionID = isExpanded ? nil : collection.id
                                }
                                💥Feedback.selection()
                            }

                            if isExpanded {
                                VStack(spacing: 0) {
                                    ForEach(reelsInCollection) { reel in
                                        Button {
                                            self.onSelectReel(reel)
                                        } label: {
                                            HomeRecentReelRow(reel: reel)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isExpanded)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CollectionsSharedTab: View {
    let inbox: [ReelFriendShare]
    let onSelectReel: (ReelItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if self.inbox.isEmpty {
                    CollectionsEmptyState(
                        symbol: "person.2",
                        title: "Nothing shared yet",
                        subtitle: "Reels and collections shared with you by friends appear here."
                    )
                } else {
                    ForEach(self.inbox.prefix(30)) { share in
                        if let reel = share.reel {
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                HStack(spacing: 12) {
                                    CachedRemoteImage(url: reel.displayThumbnailURL) {
                                        ReelThumbnailPlaceholder()
                                    }
                                    .frame(width: 72, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reel.displayTitle)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(ReelplayTheme.black)
                                            .lineLimit(1)
                                        Text("\(reel.playbackSegments.count) steps • \(reel.source.capitalized)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(ReelplayTheme.mutedText)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(ReelplayTheme.mutedText)
                                }
                                .padding(12)
                                .background(ReelplayTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelplayTheme.divider))
                            }
                            .buttonStyle(.plain)
                        } else if let collection = share.collection {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(ReelplayTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(collection.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(ReelplayTheme.black)
                                        .lineLimit(1)
                                    Text("Collection • \(collection.items?.count ?? 0) reels")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(ReelplayTheme.mutedText)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(ReelplayTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelplayTheme.divider))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CollectionsPublicTab: View {
    let socialCollections: [ReelSocialCollection]
    let onShareCollection: (ReelSocialCollection, String) async -> Void
    @State private var shareHandles: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if self.socialCollections.isEmpty {
                    CollectionsEmptyState(
                        symbol: "globe",
                        title: "No public lists",
                        subtitle: "Create a collection and publish it so others can discover your reels."
                    )
                } else {
                    ForEach(self.socialCollections) { collection in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: collection.isPublic ? "globe" : "lock.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(collection.isPublic ? ReelplayTheme.accent : ReelplayTheme.mutedText)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(collection.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(ReelplayTheme.black)
                                        .lineLimit(1)
                                    Text("\(collection.items?.count ?? 0) reels • \(collection.isPublic ? "public" : "private")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(ReelplayTheme.mutedText)
                                }
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                TextField("Share with @handle", text: Binding(
                                    get: { self.shareHandles[collection.id] ?? "" },
                                    set: { self.shareHandles[collection.id] = $0 }
                                ))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(ReelplayTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))

                                Button {
                                    let handle = self.shareHandles[collection.id] ?? ""
                                    self.shareHandles[collection.id] = ""
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    Task { await self.onShareCollection(collection, handle) }
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .background(ReelplayTheme.black)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled((self.shareHandles[collection.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(14)
                        .background(ReelplayTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CollectionsEmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: self.symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(ReelplayTheme.mutedText.opacity(0.5))
                .padding(.top, 40)
            Text(self.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)
            Text(self.subtitle)
                .font(.subheadline)
                .foregroundStyle(ReelplayTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

private struct CreateCollectionSheet: View {
    let reels: [ReelItem]
    let onCreate: (String, [UUID], Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIDs = Set<UUID>()
    @State private var isPublic = false
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !self.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ReelplayTheme.mutedText)
                            .textCase(.uppercase)

                        TextField("e.g. Morning Routines", text: self.$name)
                            .font(.body.weight(.medium))
                            .focused(self.$nameFocused)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(ReelplayTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.nameFocused ? ReelplayTheme.black.opacity(0.4) : ReelplayTheme.divider))
                            .animation(.easeInOut(duration: 0.18), value: self.nameFocused)
                    }

                    // Public toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Public Collection")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ReelplayTheme.black)
                            Text("Others can discover and save this collection")
                                .font(.caption)
                                .foregroundStyle(ReelplayTheme.mutedText)
                        }
                        Spacer()
                        Toggle("", isOn: self.$isPublic)
                            .labelsHidden()
                            .tint(ReelplayTheme.accent)
                    }
                    .padding(14)
                    .background(ReelplayTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Reel picker
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Add Reels")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ReelplayTheme.mutedText)
                                .textCase(.uppercase)
                            Spacer()
                            if !self.selectedIDs.isEmpty {
                                Text("\(self.selectedIDs.count) selected")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ReelplayTheme.accent)
                            }
                        }

                        if self.reels.isEmpty {
                            Text("No reels in your library yet")
                                .font(.subheadline)
                                .foregroundStyle(ReelplayTheme.mutedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(self.reels) { reel in
                                    let isSelected = self.selectedIDs.contains(reel.id)
                                    Button {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                            if isSelected {
                                                self.selectedIDs.remove(reel.id)
                                            } else {
                                                self.selectedIDs.insert(reel.id)
                                            }
                                        }
                                        💥Feedback.selection()
                                    } label: {
                                        HStack(spacing: 12) {
                                            CachedRemoteImage(url: reel.displayThumbnailURL) {
                                                ReelThumbnailPlaceholder()
                                            }
                                            .frame(width: 64, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(reel.displayTitle)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(ReelplayTheme.black)
                                                    .lineLimit(1)
                                                Text("\(reel.playbackSegments.count) steps")
                                                    .font(.caption)
                                                    .foregroundStyle(ReelplayTheme.mutedText)
                                            }

                                            Spacer()

                                            ZStack {
                                                Circle()
                                                    .strokeBorder(isSelected ? ReelplayTheme.black : ReelplayTheme.divider, lineWidth: 1.5)
                                                    .frame(width: 24, height: 24)
                                                if isSelected {
                                                    Circle()
                                                        .fill(ReelplayTheme.black)
                                                        .frame(width: 24, height: 24)
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isSelected)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(isSelected ? ReelplayTheme.black.opacity(0.04) : Color.clear)
                                        .animation(.easeInOut(duration: 0.14), value: isSelected)
                                    }
                                    .buttonStyle(.plain)

                                    if reel.id != self.reels.last?.id {
                                        Divider().padding(.leading, 90)
                                    }
                                }
                            }
                            .background(ReelplayTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { self.dismiss() }
                        .foregroundStyle(ReelplayTheme.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            self.isSaving = true
                            await self.onCreate(
                                self.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                Array(self.selectedIDs),
                                self.isPublic
                            )
                            self.isSaving = false
                            self.dismiss()
                        }
                    } label: {
                        if self.isSaving {
                            ProgressView().tint(ReelplayTheme.black)
                        } else {
                            Text("Create")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(self.canSave ? ReelplayTheme.black : ReelplayTheme.mutedText)
                        }
                    }
                    .disabled(!self.canSave || self.isSaving)
                }
            }
            .onAppear { self.nameFocused = true }
        }
    }
}

private struct ReelplaySearchScreen: View {
    let reels: [ReelItem]
    let socialReels: [ReelItem]
    let niches: [String]
    @Binding var searchText: String
    let onSelectReel: (ReelItem) -> Void

    private var allSearchableReels: [ReelItem] {
        var seen = Set<UUID>()
        return (self.socialReels + self.reels).filter { reel in
            seen.insert(reel.id).inserted
        }
    }

    private var filteredReels: [ReelItem] {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return self.allSearchableReels }

        return self.allSearchableReels.filter { reel in
            [
                reel.title,
                reel.caption,
                reel.summary,
                reel.creatorUsername,
                reel.category,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var categoryChips: [String] {
        let socialNames = self.niches.map { ReelCollection.displayName($0) }
        let localNames = self.reels.map(ReelCollection.categoryName(for:))
        let names = Array(Set(socialNames + localNames)).sorted()
        return Array(names.prefix(4))
    }

    private var trendingSearches: [String] {
        let titles = self.allSearchableReels
            .flatMap { reel in
                [reel.category, reel.title]
                    .compactMap { $0 }
                    .map { ReelCollection.displayName($0) }
            }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: titles).compactMap { $0 as? String }.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Search")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ReelplayTheme.black)

                HStack(spacing: 10) {
                    ReelplaySearchField(text: self.$searchText, placeholder: "Search reels, topics, or creators...")
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ReelplayTheme.black)
                            .frame(width: 42, height: 42)
                            .background(ReelplayTheme.surface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(ReelplayTheme.divider))
                    }
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(self.categoryChips, id: \.self) { chip in
                            Button {
                                self.searchText = chip
                            } label: {
                                Text(chip)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(self.searchText == chip ? .white : ReelplayTheme.black)
                                    .padding(.horizontal, 18)
                                    .frame(height: 40)
                                    .background(self.searchText == chip ? ReelplayTheme.black : ReelplayTheme.surface)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(ReelplayTheme.divider))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending Searches")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    FlowLayout(items: self.trendingSearches) { item in
                        Button {
                            self.searchText = item
                        } label: {
                            Text(item)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ReelplayTheme.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(ReelplayTheme.softSurface.opacity(0.58))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(self.socialReels.isEmpty ? "Top Reels" : "Popular Shared Reels")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    if self.filteredReels.isEmpty {
                        Text("No reels found")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ReelplayTheme.mutedText)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(self.filteredReels.prefix(8)) { reel in
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                SearchResultCard(reel: reel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReelplayProfileScreen: View {
    let reels: [ReelItem]
    let profile: ReelSocialProfile?
    let handle: String
    let bookmarkedReelIDs: [UUID]
    let publicReelIDs: [UUID]
    let collections: [ReelCollection]
    let friends: [ReelFriendship]
    let incomingFriendRequests: [ReelFriendship]
    let outgoingFriendRequests: [ReelFriendship]
    let inbox: [ReelFriendShare]
    let onSaveHandle: (String) async -> Void
    let onAddFriend: (String) async -> Void
    let onRespondToFriendRequest: (ReelFriendship, Bool) async -> Void
    let onPublishSavedList: () async -> Void
    let onSelectReel: (ReelItem) -> Void
    @State private var draftHandle = ""
    @State private var friendHandle = ""

    private var savedReels: [ReelItem] {
        let ids = Set(self.bookmarkedReelIDs)
        let bookmarked = self.reels.filter { ids.contains($0.id) }
        return bookmarked.isEmpty ? Array(self.reels.prefix(10)) : bookmarked
    }

    private var savedHours: Int {
        max(1, self.savedReels.compactMap(\.durationSeconds).reduce(0, +) / 3600)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Image(systemName: "gearshape")
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ReelplayTheme.black)
                }

                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(ReelplayTheme.accent.opacity(0.72))
                        .frame(width: 82, height: 82)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(ReelplayTheme.black)
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(self.profileName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black)
                        Text("@\(self.profile?.handle ?? self.handle)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ReelplayTheme.mutedText)
                        Text("\(self.friends.count) friends • \(self.bookmarkedReelIDs.count) saved • \(self.publicReelIDs.count) public")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your handle")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    HStack(spacing: 10) {
                        TextField("handle", text: self.$draftHandle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(ReelplayTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))

                        Button {
                            Task { await self.onSaveHandle(self.draftHandle) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(ReelplayTheme.black)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(self.draftHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add friend")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    HStack(spacing: 10) {
                        TextField("@friend", text: self.$friendHandle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(ReelplayTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))

                        Button {
                            let handle = self.friendHandle
                            self.friendHandle = ""
                            Task { await self.onAddFriend(handle) }
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(ReelplayTheme.black)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(self.friendHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !self.incomingFriendRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Friend requests")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black)

                        ForEach(self.incomingFriendRequests) { request in
                            FriendRequestRow(
                                friendship: request,
                                onAccept: { Task { await self.onRespondToFriendRequest(request, true) } },
                                onDecline: { Task { await self.onRespondToFriendRequest(request, false) } }
                            )
                        }
                    }
                }

                if !self.friends.isEmpty || !self.outgoingFriendRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Friends")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black)

                        ForEach(self.friends) { friendship in
                            FriendCompactRow(friendship: friendship, status: "Friend")
                        }

                        ForEach(self.outgoingFriendRequests) { friendship in
                            FriendCompactRow(friendship: friendship, status: "Pending")
                        }
                    }
                }

                Button {
                    Task { await self.onPublishSavedList() }
                } label: {
                    Label("Share saved list", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(ReelplayTheme.softSurface.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                HStack(spacing: 0) {
                    ForEach(["Saved", "History", "Liked"], id: \.self) { tab in
                        Text(tab)
                            .font(.subheadline.weight(tab == "Saved" ? .bold : .medium))
                            .foregroundStyle(tab == "Saved" ? ReelplayTheme.black : ReelplayTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(tab == "Saved" ? ReelplayTheme.black : .clear)
                                    .frame(height: 2)
                            }
                    }
                }

                VStack(spacing: 10) {
                    ForEach(self.inbox.compactMap(\.reel).prefix(5)) { reel in
                        Button {
                            self.onSelectReel(reel)
                        } label: {
                            ProfileSavedReelRow(reel: reel)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(self.savedReels.prefix(10)) { reel in
                        Button {
                            self.onSelectReel(reel)
                        } label: {
                            ProfileSavedReelRow(reel: reel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if self.draftHandle.isEmpty {
                self.draftHandle = self.profile?.handle ?? self.handle
            }
        }
        .onChange(of: self.profile?.handle) { _, value in
            if let value {
                self.draftHandle = value
            }
        }
    }

    private var profileName: String {
        self.reels.first?.creatorDisplayName ?? "Reelplay User"
    }

}

private struct FriendRequestRow: View {
    let friendship: ReelFriendship
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(profile: self.friendship.otherProfile)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.friendship.otherProfile?.displayName ?? "Reelplay User")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                Text("@\(self.friendship.otherProfile?.handle ?? "unknown")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReelplayTheme.mutedText)
            }

            Spacer()

            Button(action: self.onDecline) {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
                    .background(ReelplayTheme.softSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: self.onAccept) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(ReelplayTheme.black)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
    }
}

private struct FriendCompactRow: View {
    let friendship: ReelFriendship
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(profile: self.friendship.otherProfile)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.friendship.otherProfile?.displayName ?? "Reelplay User")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                Text("@\(self.friendship.otherProfile?.handle ?? "unknown")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReelplayTheme.mutedText)
            }

            Spacer()

            Text(self.status)
                .font(.caption.weight(.bold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.62))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(ReelplayTheme.softSurface.opacity(0.72))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
    }
}

private struct FriendAvatar: View {
    let profile: ReelSocialProfile?

    var body: some View {
        Circle()
            .fill(ReelplayTheme.accent.opacity(0.64))
            .frame(width: 42, height: 42)
            .overlay {
                Text(String((self.profile?.handle ?? "r").prefix(1)).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
            }
    }
}

private struct ReelplayTabBar: View {
    @Binding var selectedTab: ReelplayTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReelplayTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        self.selectedTab = tab
                    }
                    💥Feedback.selection()
                } label: {
                    ReelplayTabItem(tab: tab, isSelected: self.selectedTab == tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(ReelplayTheme.surface)
        .shadow(color: .black.opacity(0.045), radius: 12, y: -4)
        .padding(.horizontal, 0)
        .padding(.bottom, 0)
        .background(ReelplayTheme.surface.ignoresSafeArea(edges: .bottom))
    }
}

private struct ReelplayTabItem: View {
    let tab: ReelplayTab
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            if self.tab == .add {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xB38A4A), Color(hex: 0x8B6632)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 4))
                        .shadow(color: Color(hex: 0x8B6632).opacity(0.24), radius: 10, y: 5)

                    Image(systemName: "link")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: -7)

                Text("Import Reel")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ReelplayTheme.black.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .offset(y: -10)
            } else {
                Image(systemName: self.tab.symbol)
                    .font(.system(size: 22, weight: self.isSelected ? .bold : .regular))
                    .foregroundStyle(self.isSelected ? ReelplayTheme.black : ReelplayTheme.black.opacity(0.58))
                    .frame(height: 26)

                Text(self.tab.title)
                    .font(.caption2.weight(self.isSelected ? .bold : .regular))
                    .foregroundStyle(self.isSelected ? ReelplayTheme.black : ReelplayTheme.black.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

private struct ReelCollection: Identifiable {
    let name: String
    let count: Int

    var id: String { self.name.lowercased() }

    var symbol: String {
        let value = self.name.lowercased()
        return switch value {
            case let value where value.contains("workout") || value.contains("fitness") || value.contains("gym") || value.contains("exercise") || value.contains("strength"):
                "dumbbell"
            case let value where value.contains("recipe") || value.contains("food") || value.contains("meal") || value.contains("protein") || value.contains("cook"):
                "takeoutbag.and.cup.and.straw"
            case let value where value.contains("golf") || value.contains("sport") || value.contains("ball") || value.contains("game"):
                "flag.fill"
            case let value where value.contains("travel") || value.contains("flight") || value.contains("trip"):
                "airplane"
            case let value where value.contains("skin") || value.contains("beauty") || value.contains("care"):
                "leaf"
            case let value where value.contains("music") || value.contains("dance"):
                "music.note"
            case let value where value.contains("business") || value.contains("money") || value.contains("finance") || value.contains("startup"):
                "briefcase"
            case let value where value.contains("learn") || value.contains("education") || value.contains("tutorial") || value.contains("lesson"):
                "book"
            case let value where value.contains("style") || value.contains("fashion") || value.contains("outfit"):
                "tshirt"
            case let value where value.contains("tech") || value.contains("code") || value.contains("software"):
                "desktopcomputer"
            case let value where value.contains("home") || value.contains("interior") || value.contains("decor"):
                "house"
            case let value where value.contains("mind") || value.contains("productivity") || value.contains("routine"):
                "clock"
            default:
                Self.fallbackSymbols[Self.stableIndex(for: self.name, count: Self.fallbackSymbols.count)]
        }
    }

    var tint: Color {
        let value = self.name.lowercased()
        return switch value {
            case let value where value.contains("workout") || value.contains("fitness") || value.contains("gym") || value.contains("exercise") || value.contains("strength"):
                Color(hex: 0xD4C7A7)
            case let value where value.contains("recipe") || value.contains("food") || value.contains("meal") || value.contains("protein") || value.contains("cook"):
                Color(hex: 0xEFE4CF)
            case let value where value.contains("golf") || value.contains("sport") || value.contains("ball") || value.contains("game"):
                Color(hex: 0xDCE8DD)
            case let value where value.contains("travel") || value.contains("flight") || value.contains("trip"):
                Color(hex: 0xE4E9EF)
            case let value where value.contains("skin") || value.contains("beauty") || value.contains("care"):
                Color(hex: 0xDDEBDD)
            case let value where value.contains("music") || value.contains("dance"):
                Color(hex: 0xE7DFEE)
            case let value where value.contains("business") || value.contains("money") || value.contains("finance") || value.contains("startup"):
                Color(hex: 0xE6E2D3)
            case let value where value.contains("learn") || value.contains("education") || value.contains("tutorial") || value.contains("lesson"):
                Color(hex: 0xE2E8EF)
            default:
                Self.fallbackTints[Self.stableIndex(for: self.name, count: Self.fallbackTints.count)]
        }
    }

    var iconColor: Color {
        let value = self.name.lowercased()
        return switch value {
            case let value where value.contains("workout") || value.contains("fitness") || value.contains("gym") || value.contains("exercise") || value.contains("strength"):
                Color(hex: 0x7A5428)
            case let value where value.contains("recipe") || value.contains("food") || value.contains("meal") || value.contains("protein") || value.contains("cook"):
                Color(hex: 0xD78315)
            case let value where value.contains("golf") || value.contains("sport") || value.contains("ball") || value.contains("game"):
                Color(hex: 0x4E7358)
            case let value where value.contains("travel") || value.contains("flight") || value.contains("trip"):
                Color(hex: 0x5F7896)
            case let value where value.contains("skin") || value.contains("beauty") || value.contains("care"):
                Color(hex: 0x678B62)
            default:
                Self.fallbackIconColors[Self.stableIndex(for: self.name, count: Self.fallbackIconColors.count)]
        }
    }

    static func categoryName(for reel: ReelItem) -> String {
        if let category = reel.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            return Self.displayName(category)
        }

        let searchable = [
            reel.title,
            reel.caption,
            reel.summary,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if searchable.contains("workout") || searchable.contains("push") || searchable.contains("bench") || searchable.contains("fitness") {
            return "Workouts"
        }
        if searchable.contains("recipe") || searchable.contains("protein") || searchable.contains("meal") || searchable.contains("breakfast") {
            return "Recipes"
        }
        if searchable.contains("golf") || searchable.contains("swing") {
            return "Golf"
        }
        if searchable.contains("travel") || searchable.contains("flight") {
            return "Travel"
        }
        if searchable.contains("skin") || searchable.contains("care") {
            return "Skincare"
        }
        if searchable.contains("music") || searchable.contains("dance") || searchable.contains("song") {
            return "Music"
        }
        return "Notes & Ideas"
    }

    static func displayName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private static let fallbackSymbols = [
        "sparkles",
        "lightbulb",
        "target",
        "camera",
        "play.rectangle",
        "bolt",
        "wand.and.stars",
        "bookmark",
        "person.crop.rectangle",
        "square.stack",
        "scope",
        "flag",
    ]

    private static let fallbackTints = [
        Color(hex: 0xEFE4CF),
        Color(hex: 0xE8E5DF),
        Color(hex: 0xDCE8DD),
        Color(hex: 0xE4E9EF),
        Color(hex: 0xE7DFEE),
        Color(hex: 0xF0E6D7),
        Color(hex: 0xE2E8D8),
        Color(hex: 0xE6E2D3),
    ]

    private static let fallbackIconColors = [
        Color(hex: 0x8A642D),
        Color(hex: 0x5D5A52),
        Color(hex: 0x5A765B),
        Color(hex: 0x5F7896),
        Color(hex: 0x7B678D),
        Color(hex: 0x9B6C41),
        Color(hex: 0x6C7B4E),
        Color(hex: 0x7A6A4D),
    ]

    private static func stableIndex(for value: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let total = value.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
        return abs(total) % count
    }
}

private struct SectionHeader: View {
    let title: String
    var actionTitle: String?

    var body: some View {
        HStack {
            Text(self.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)

            Spacer()

            if let actionTitle {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReelplayTheme.black.opacity(0.72))
            }
        }
    }
}

private struct ReelplaySearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.45))

            TextField(self.placeholder, text: self.$text)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(self.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)

            Spacer()

            if let actionTitle {
                HStack(spacing: 7) {
                    Text(actionTitle)
                    if actionTitle.lowercased() != "clear" {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.62))
            }
        }
    }
}

private struct HomeHeroImportCard: View {
    let featuredReel: ReelItem?
    let onImport: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            ReelplayTheme.surface,
                            Color(hex: 0xF4EBDD),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18)
                .stroke(ReelplayTheme.divider, lineWidth: 1)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paste a reel.\nGet smart steps.")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Instagram, TikTok")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ReelplayTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Button(action: self.onImport) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 17, weight: .bold))
                            Text("Paste Link")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 52)
                        .background(ReelplayTheme.black)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    HeroReelPreview(reel: self.featuredReel)
                        .frame(width: 106, height: 140)
                        .rotationEffect(.degrees(-8))
                        .offset(x: -34, y: 1)

                    SmartStepsPreview(reel: self.featuredReel)
                        .frame(width: 132, height: 108)
                        .rotationEffect(.degrees(7))
                        .offset(x: 28, y: 22)

                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color(hex: 0x9B7A45))
                        .offset(x: 76, y: -54)
                }
                .frame(width: 154, height: 158)
            }
            .padding(22)
        }
        .frame(minHeight: 196)
        .frame(maxWidth: .infinity)
        .clipped()
        .shadow(color: .black.opacity(0.05), radius: 18, y: 9)
    }
}

private struct HeroReelPreview: View {
    let reel: ReelItem?

    var body: some View {
        ZStack {
            CachedRemoteImage(url: self.reel?.displayThumbnailURL) {
                ReelThumbnailPlaceholder()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "play.fill")
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 8)

            Image(systemName: self.reel?.source.lowercased() == "tiktok" ? "music.note" : "camera")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xFF6A88), Color(hex: 0x6C5CE7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct SmartStepsPreview: View {
    let reel: ReelItem?

    private var previewSegments: [ReelSegment] {
        Array((self.reel?.playbackSegments ?? []).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Smart Steps")
                .font(.caption.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)

            ForEach(Array(self.rows.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 7) {
                    Image(systemName: index == 0 ? "checkmark.circle.fill" : index == 1 ? "play.circle.fill" : "circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(index == 1 ? Color(hex: 0x9B7A45) : ReelplayTheme.black.opacity(index == 2 ? 0.18 : 0.38))

                    Text("\(index + 1) \(title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReelplayTheme.black.opacity(index == 2 ? 0.38 : 0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.horizontal, 8)
                .frame(height: 27)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(index == 1 ? ReelplayTheme.accent.opacity(0.32) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(13)
        .background(ReelplayTheme.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }

    private var rows: [String] {
        let titles = self.previewSegments.map(\.title)
        if titles.count >= 3 { return titles }
        return titles + ["Warm-up", "Setup", "Replay"].dropFirst(titles.count)
    }
}

private struct HomeSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.45))

            TextField("Search your reels or topics...", text: self.$text)
                .font(.system(size: 17, weight: .regular))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Rectangle()
                .fill(ReelplayTheme.divider)
                .frame(width: 1, height: 32)
                .padding(.leading, 6)

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.56))
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(ReelplayTheme.surface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
    }
}

private struct ContinuePlayingCard: View {
    let reel: ReelItem
    var onMenuTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                    ReelThumbnailPlaceholder()
                }
                .frame(width: 102, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(self.durationText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(self.reel.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 8)

                    Button {
                        self.onMenuTap?()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 7) {
                    Text("Step \(self.currentStep) of \(self.totalSteps)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)

                    ProgressView(value: Double(self.currentStep), total: Double(self.totalSteps))
                        .tint(ReelplayTheme.accent)
                        .background(ReelplayTheme.black.opacity(0.08))
                        .clipShape(Capsule())
                        .frame(width: 72, height: 4)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ReelplayTheme.mutedText)

                Text(self.activeStepTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        HomePill(symbol: "sparkles", text: "AI summarized")
                        HomePill(symbol: "clock", text: self.durationText)
                        HomePill(symbol: self.reel.source.lowercased() == "tiktok" ? "music.note" : "camera", text: self.reel.source.capitalized)
                    }

                    HStack(spacing: 7) {
                        HomePill(symbol: "clock", text: self.durationText)
                        HomePill(symbol: self.reel.source.lowercased() == "tiktok" ? "music.note" : "camera", text: self.reel.source.capitalized)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(ReelplayTheme.black)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
        }
        .padding(12)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var totalSteps: Int {
        max(self.reel.playbackSegments.count, 1)
    }

    private var currentStep: Int {
        min(max(1, self.totalSteps / 2), self.totalSteps)
    }

    private var activeStepTitle: String {
        self.reel.playbackSegments.dropFirst(max(0, self.currentStep - 1)).first?.title ?? "Ready to replay"
    }

    private var durationText: String {
        self.reel.durationDisplayText
    }
}

private struct HomeCollectionCard: View {
    let collection: ReelCollection
    var isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(self.collection.tint.opacity(0.82))
                    Image(systemName: self.collection.symbol)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(self.collection.iconColor)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(self.collection.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text("\(self.collection.count) \(self.collection.count == 1 ? "reel" : "reels")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.58))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)

            FlowLines()
                .stroke(self.collection.iconColor.opacity(0.12), lineWidth: 1)
                .frame(width: 150, height: 68)
                .offset(x: 18, y: -10)
        }
        .frame(width: 180, height: 150)
        .background(
            LinearGradient(
                colors: [
                    self.collection.tint.opacity(0.32),
                    ReelplayTheme.surface.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.isSelected ? ReelplayTheme.black.opacity(0.34) : ReelplayTheme.divider, lineWidth: self.isSelected ? 1.5 : 1))
    }
}

private struct FlowLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<5 {
            let offset = CGFloat(index) * 10
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + offset))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY - 34 + offset),
                control1: CGPoint(x: rect.minX + 44, y: rect.midY - 18 + offset),
                control2: CGPoint(x: rect.maxX - 44, y: rect.midY + 22 - offset)
            )
        }
        return path
    }
}

private struct ReelActionMenu: View {
    let reel: ReelItem
    let onShare: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)

                    HStack(spacing: 12) {
                        CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                            ReelThumbnailPlaceholder()
                        }
                        .frame(width: 52, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(self.reel.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(self.reel.displayCreator)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                Divider().padding(.horizontal, 20)

                ShareLink(item: self.reel.sourceURL) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text("Share")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { self.onShare() })

                Divider().padding(.horizontal, 20)

                Button(role: .destructive) {
                    self.onDelete()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text("Delete")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.bottom, 32)
        }
        .ignoresSafeArea()
    }
}

private struct HomeRecentReelRow: View {
    let reel: ReelItem
    var onMenuTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                    ReelThumbnailPlaceholder()
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(self.reel.durationDisplayText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(self.reel.displayTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)

                Text(self.reel.displayCreator)
                    .font(.subheadline)
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(self.reel.playbackSegments.count) smart steps", systemImage: "list.bullet")
                    Text("•")
                    Label(self.reel.durationDisplayText, systemImage: "clock")
                    Text("•")
                    Label(self.reel.source.capitalized, systemImage: self.reel.source.lowercased() == "tiktok" ? "music.note" : "camera")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            VStack(spacing: 15) {
                Button {
                    self.onMenuTap?()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.55))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(ReelplayTheme.black)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.14), radius: 9, y: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ReelplayTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ReelplayTheme.divider)
                .frame(height: 1)
                .padding(.leading, 124)
        }
    }
}

private struct HomePill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(self.text, systemImage: self.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(ReelplayTheme.black.opacity(0.62))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(ReelplayTheme.black.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct ImportSource {
    let name: String
    let symbol: String
    let color: Color
}

private struct ImportSourceOption: View {
    let source: ImportSource
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: self.source.symbol)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(self.source.color)
                .frame(width: 64, height: 64)
                .background(ReelplayTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(self.isSelected ? ReelplayTheme.black : ReelplayTheme.divider, lineWidth: self.isSelected ? 1.5 : 1))

            Text(self.source.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReelplayTheme.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 86)
    }
}

private struct SearchResultCard: View {
    let reel: ReelItem

    var body: some View {
        HStack(spacing: 12) {
            ReelThumbnailBadge(reel: self.reel, width: 86, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(self.reel.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)

                Text(self.reel.displayCreator)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text("\(self.reel.playbackSegments.count) steps")
                    Text("•")
                    Text(self.reel.source.capitalized)
                }
                .font(.caption)
                .foregroundStyle(ReelplayTheme.black.opacity(0.48))
            }

            Spacer()

            Image(systemName: "bookmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.72))
        }
        .padding(8)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))
    }
}

private struct CompactReelCard: View {
    let reel: ReelItem

    var body: some View {
        HStack(spacing: 12) {
            ReelThumbnailBadge(reel: self.reel, width: 82, height: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text(self.reel.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)
                Text("\(self.reel.playbackSegments.count) steps • \(self.reel.source.capitalized)")
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.56))
        }
        .padding(10)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))
    }
}

private struct CollectionLibraryCard: View {
    let collection: ReelCollection
    let reels: [ReelItem]
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: self.collection.symbol)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(self.collection.iconColor)
                .frame(width: 52, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.collection.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black)
                            .lineLimit(1)
                        Text("\(self.collection.count) \(self.collection.count == 1 ? "reel" : "reels")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ReelplayTheme.mutedText)
                    }

                    Spacer()

                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.58))
                }

                HStack(spacing: 5) {
                    ForEach(Array(self.reels.prefix(3).enumerated()), id: \.element.id) { _, reel in
                        CachedRemoteImage(url: reel.displayThumbnailURL) {
                            ReelThumbnailPlaceholder()
                        }
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if self.reels.count > 3 {
                        Text("+\(self.reels.count - 3)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.62))
                            .frame(width: 46, height: 42)
                            .background(ReelplayTheme.softSurface.opacity(0.68))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    self.collection.tint.opacity(self.isSelected ? 0.34 : 0.22),
                    ReelplayTheme.surface,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.isSelected ? ReelplayTheme.black.opacity(0.34) : ReelplayTheme.divider, lineWidth: self.isSelected ? 1.4 : 1))
    }
}

private struct ProfileSavedReelRow: View {
    let reel: ReelItem

    var body: some View {
        HStack(spacing: 12) {
            ReelThumbnailBadge(reel: self.reel, width: 86, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(self.reel.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(2)
                Text("\(self.reel.playbackSegments.count) steps • \(self.reel.source.capitalized)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReelplayTheme.mutedText)
            }

            Spacer()

            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.58))
        }
        .padding(8)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))
    }
}

private struct ReelThumbnailBadge: View {
    let reel: ReelItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                ReelThumbnailPlaceholder()
            }

            Text(self.reel.durationDisplayText)
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72))
                .clipShape(Capsule())
                .padding(5)
        }
        .frame(width: self.width, height: self.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CollectionMiniCard: View {
    let collection: ReelCollection
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.collection.tint.opacity(0.42))
                Image(systemName: self.collection.symbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(self.collection.iconColor)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.collection.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .truncationMode(.tail)

                Text("\(self.collection.count) reels")
                    .font(.caption2)
                    .foregroundStyle(ReelplayTheme.mutedText)
            }
        }
        .padding(10)
        .frame(width: 96, height: 118, alignment: .leading)
        .background(self.collection.tint.opacity(self.isSelected ? 0.34 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(self.isSelected ? ReelplayTheme.black.opacity(0.42) : .clear, lineWidth: 1.5))
    }
}

private struct CollectionListCard: View {
    let collection: ReelCollection
    var isSelected = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.collection.tint.opacity(0.4))

                Image(systemName: self.collection.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(self.collection.iconColor)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.collection.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .truncationMode(.tail)

                Text("\(self.collection.count) reels")
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.58))
        }
        .padding(10)
        .background(self.isSelected ? self.collection.tint.opacity(0.22) : ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(self.isSelected ? ReelplayTheme.black.opacity(0.28) : ReelplayTheme.divider))
    }
}

private struct ReelListRow: View {
    let reel: ReelItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                    ReelThumbnailPlaceholder()
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(self.durationText)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(self.reel.title ?? self.reel.caption ?? "Saved reel")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(2)

                Text(self.reel.creatorUsername.map { "@\($0)" } ?? self.reel.source.capitalized)
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)

                HStack(spacing: 8) {
                    Text("\(self.reel.segments.count) steps")
                    Text("•")
                    Text(self.reel.source.capitalized)
                }
                .font(.caption2)
                .foregroundStyle(ReelplayTheme.black.opacity(0.45))
            }

            Spacer()

            Image(systemName: "ellipsis")
                .foregroundStyle(ReelplayTheme.black.opacity(0.7))
        }
        .padding(10)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReelplayTheme.divider))
    }

    private var durationText: String {
        guard let seconds = self.reel.durationSeconds else { return "--:--" }
        return SegmentPageView.format(seconds)
    }
}

private struct ReelRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(ReelplayTheme.softSurface)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ReelplayTheme.softSurface)
                    .frame(height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ReelplayTheme.softSurface)
                    .frame(width: 160, height: 11)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ReelplayTheme.softSurface)
                    .frame(width: 110, height: 10)
            }
        }
        .padding(10)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReelThumbnailPlaceholder: View {
    var body: some View {
        ZStack {
            ReelplayTheme.softSurface
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.5))
        }
    }
}

private struct HomeInitialLibraryState: View {
    let isLoading: Bool
    let maxWidth: CGFloat
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if self.isLoading {
                PremiumHomeLoadingCard(maxWidth: self.maxWidth)
            } else {
                EmptyHomeCard(maxWidth: self.maxWidth, onImport: self.onImport)
                EmptyLibraryPreviewGrid(maxWidth: self.maxWidth)
            }
        }
        .frame(width: self.maxWidth, alignment: .leading)
        .transition(.opacity)
    }
}

private struct EmptyLibraryPreviewGrid: View {
    let maxWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your library will organize itself")
                .font(.headline.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)

            HStack(spacing: 10) {
                EmptyLibraryPreviewTile(
                    symbol: "play.rectangle.fill",
                    title: "Continue",
                    subtitle: "Resume the last reel you opened"
                )

                EmptyLibraryPreviewTile(
                    symbol: "folder.fill",
                    title: "Collections",
                    subtitle: "Grouped by topics and saved lists"
                )
            }

            EmptyLibraryPreviewTile(
                symbol: "clock.arrow.circlepath",
                title: "Recently Added",
                subtitle: "New imports appear here in chronological order",
                isWide: true
            )
        }
        .frame(width: max(0, self.maxWidth - 32), alignment: .leading)
        .padding(16)
        .frame(width: self.maxWidth, alignment: .leading)
        .background(ReelplayTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelplayTheme.divider))
    }
}

private struct EmptyLibraryPreviewTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    var isWide = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x9B7A45))
                .frame(width: 32, height: 32)
                .background(ReelplayTheme.accent.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .lineLimit(self.isWide ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: self.isWide ? 74 : 112, alignment: .topLeading)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReelplayTheme.divider))
    }
}

private struct HomeReservedCard<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        self.content()
            .frame(maxWidth: .infinity, minHeight: self.height, alignment: .leading)
            .background(ReelplayTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayTheme.divider))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
    }
}

private struct InitialStateThumbnail: View {
    let isLoading: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(ReelplayTheme.softSurface.opacity(0.72))

            ReelplayAppIconView()
                .frame(width: 42, height: 42)
                .opacity(0.82)
        }
        .frame(width: 96, height: 72)
        .shimmering(self.isLoading)
    }
}

private struct InitialStateLine: View {
    let width: CGFloat
    let height: CGFloat
    let isLoading: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: self.height / 2)
            .fill(ReelplayTheme.softSurface.opacity(0.78))
            .frame(width: self.width, height: self.height)
            .shimmering(self.isLoading)
    }
}

private struct ReelplayShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = -0.7

    func body(content: Content) -> some View {
        content
            .overlay {
                if self.isActive {
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.38),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: self.phase * 260)
                    .blendMode(.plusLighter)
                    .onAppear {
                        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                            self.phase = 0.9
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func shimmering(_ isActive: Bool) -> some View {
        self.modifier(ReelplayShimmerModifier(isActive: isActive))
    }
}

private final class ReelplayImageCache {
    static let shared = ReelplayImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        self.cache.countLimit = 240
        self.cache.totalCostLimit = 72 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        self.cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        self.cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

private struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var failedURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: self.contentMode)
            } else {
                self.placeholder()
            }
        }
        .task(id: self.url?.absoluteString ?? "missing") {
            await self.load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            self.image = nil
            return
        }

        if let cached = ReelplayImageCache.shared.image(for: url.absoluteString) {
            self.image = cached
            return
        }

        guard self.failedURL != url else { return }
        self.image = nil

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else {
                self.failedURL = url
                return
            }

            ReelplayImageCache.shared.set(image, for: url.absoluteString)
            self.image = image
        } catch {
            self.failedURL = url
        }
    }
}

private struct EmptyHomeCard: View {
    let maxWidth: CGFloat
    let onImport: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save your first reel")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                Text("Paste or share an Instagram or TikTok link and Reelplay will build replayable microreels from the moments that matter.")
                    .font(.subheadline)
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: self.onImport) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Reel")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(ReelplayTheme.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            EmptyReelPreviewPanel()
                .frame(width: max(0, self.maxWidth - 32), height: 172)
        }
        .frame(width: max(0, self.maxWidth - 32), alignment: .leading)
        .padding(16)
        .frame(width: self.maxWidth, alignment: .leading)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 22, y: 10)
        .opacity(self.appeared ? 1 : 0)
        .scaleEffect(self.appeared ? 1 : 0.985)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                self.appeared = true
            }
        }
    }
}

private struct EmptyReelPreviewPanel: View {
    var title = "Replay any reel"
    var subtitle = "Saved moments become timestamped steps."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(self.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 16) {
                ReelplayAppIconView()
                    .frame(width: 70, height: 70)
                    .shadow(color: .black.opacity(0.32), radius: 12, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["00:04", "00:11", "00:18"], id: \.self) { time in
                        HStack(spacing: 10) {
                            Text(time)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(ReelplayTheme.accent)
                                .frame(width: 42, alignment: .leading)

                            Capsule()
                                .fill(.white.opacity(time == "00:11" ? 0.24 : 0.34))
                                .frame(height: 6)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Capsule()
                    .fill(ReelplayTheme.accent)
                    .frame(width: 42, height: 6)
                ForEach(0..<4) { _ in
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 28, height: 6)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [ReelplayTheme.black, Color(hex: 0x1C1C1E)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PremiumHomeLoadingCard: View {
    let maxWidth: CGFloat
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EmptyReelPreviewPanel(title: "Preparing your library", subtitle: "Syncing saved reels and pending microreels.")
                .frame(width: max(0, self.maxWidth - 32), height: 172)
                .overlay(alignment: .topTrailing) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.86)
                        .padding(18)
                }

            HStack(spacing: 10) {
                ForEach(["Reading", "OCR", "Segments"], id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.66))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(ReelplayTheme.softSurface.opacity(0.52))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(width: max(0, self.maxWidth - 32), alignment: .leading)
        .padding(16)
        .frame(width: self.maxWidth, alignment: .leading)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 22, y: 10)
        .opacity(self.pulse ? 0.72 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
    }
}

private struct ReelplayPreviewPanel: View {
    var title = "Replay smarter"
    var subtitle = "Microreels are built from key moments."
    var isLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            ReelplayTheme.black,
                            Color(hex: 0x1C1C1E),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(self.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(self.subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if self.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.86)
                    }
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 14) {
                    ReelplayAppIconView()
                        .frame(width: 86, height: 86)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(self.previewRows, id: \.0) { row in
                            HStack(spacing: 8) {
                                Text(row.0)
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(ReelplayTheme.accent)
                                    .frame(width: 42, alignment: .leading)
                                Capsule()
                                    .fill(.white.opacity(row.2))
                                    .frame(width: row.1, height: 7)
                            }
                        }
                        .redacted(reason: self.isLoading ? .placeholder : [])
                    }

                    Spacer()
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == 0 ? ReelplayTheme.accent : .white.opacity(0.16))
                            .frame(width: index == 0 ? 34 : 18, height: 5)
                    }
                }
            }
            .padding(18)
        }
    }

    private var previewRows: [(String, CGFloat, Double)] {
        [
            ("00:04", 132, 0.32),
            ("00:11", 104, 0.24),
            ("00:18", 156, 0.28),
        ]
    }
}

private struct ReelplayAppIconView: View {
    var body: some View {
        Image("AboutAppIcon")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
    }
}

private struct ImportStepRow: View {
    let symbol: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ReelplayTheme.accent.opacity(0.28))
                Image(systemName: self.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ReelplayTheme.black)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                Text(self.bodyText)
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SearchSuggestions: View {
    private let recent = ["chest workout", "protein breakfast", "golf swing", "skin care routine"]
    private let trending = ["Push workout", "High protein meals", "Morning routine", "Driver swing tip", "Glute workout"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Searches")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.62))
                }

                FlowLayout(items: self.recent) { item in
                    Text(item)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ReelplayTheme.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(ReelplayTheme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ReelplayTheme.divider))
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Trending Searches")
                    .font(.subheadline.weight(.bold))

                ForEach(self.trending, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(ReelplayTheme.black)
                }
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let items: [String]
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    let content: (String) -> Content

    var body: some View {
        FlowLayoutContainer(items: self.items, horizontalSpacing: self.horizontalSpacing, verticalSpacing: self.verticalSpacing, content: self.content)
    }
}

private struct FlowLayoutContainer<Content: View>: View {
    let items: [String]
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let content: (String) -> Content
    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { proxy in
            self.generateContent(in: proxy)
        }
        .frame(height: self.totalHeight)
    }

    private func generateContent(in proxy: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(self.items, id: \.self) { item in
                self.content(item)
                    .alignmentGuide(.leading) { dimensions in
                        if abs(width - dimensions.width) > proxy.size.width {
                            width = 0
                            height -= dimensions.height + self.verticalSpacing
                        }

                        let result = width
                        width -= dimensions.width + self.horizontalSpacing
                        return result
                    }
                    .alignmentGuide(.top) { dimensions in
                        let result = height
                        if item == self.items.last {
                            width = 0
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(self.heightReader)
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: FlowLayoutHeightPreferenceKey.self, value: proxy.size.height)
        }
        .onPreferenceChange(FlowLayoutHeightPreferenceKey.self) { height in
            guard abs(self.totalHeight - height) > 0.5 else { return }
            self.totalHeight = height
        }
    }
}

private struct FlowLayoutHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(self.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(ReelplayTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileMenuRow: View {
    let symbol: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)
            Text(self.title)
                .font(.subheadline.weight(.medium))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(ReelplayTheme.mutedText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.42))
        }
        .foregroundStyle(ReelplayTheme.black)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ReelplayTheme.divider)
                .frame(height: 1)
                .padding(.leading, 50)
        }
    }
}

private struct ImportReelOverlay: View {
    let title: String
    let headline: String
    let subheadline: String
    let footer: String
    let sourceURL: URL?
    let stages: [String]
    let activeStageIndex: Int
    let progress: Double
    let encouragement: String?
    @State private var pulse = false

    private var clampedProgress: Double {
        min(max(self.progress, 0.01), 0.99)
    }

    private var progressPercent: Int {
        Int((self.clampedProgress * 100).rounded())
    }

    var body: some View {
        ZStack {
            ReelplayTheme.background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .opacity(0)

                    Spacer()

                    Text(self.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    Spacer()

                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(ReelplayTheme.softSurface, lineWidth: 7)
                        .frame(width: 176, height: 176)

                    Circle()
                        .trim(from: 0, to: self.clampedProgress)
                        .stroke(ReelplayTheme.black, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 176, height: 176)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: self.clampedProgress)

                    VStack(spacing: 7) {
                        ReelplayAppIconView()
                            .frame(width: 82, height: 82)
                            .scaleEffect(self.pulse ? 1.05 : 0.97)

                        Text("\(self.progressPercent)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.72))
                            .monospacedDigit()
                    }
                }

                VStack(spacing: 9) {
                    Text(self.headline)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    Text(self.subheadline)
                        .font(.footnote)
                        .foregroundStyle(ReelplayTheme.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    if let encouragement {
                        Text(encouragement)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let sourceURL {
                        Text(sourceURL.host(percentEncoded: false) ?? sourceURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(ReelplayTheme.black.opacity(0.44))
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                    }
                }

                VStack(spacing: 18) {
                    ForEach(Array(self.stages.enumerated()), id: \.offset) { index, stage in
                        HStack {
                            Text(stage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ReelplayTheme.black)

                            Spacer()

                            if index < self.activeStageIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ReelplayTheme.black)
                            } else if index == self.activeStageIndex {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(ReelplayTheme.black)
                                    .symbolEffect(.pulse)
                            } else {
                                Circle()
                                    .stroke(ReelplayTheme.black.opacity(0.22), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(self.footer)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.7))
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(ReelplayTheme.accent.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
    }
}

private struct ReelplayMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<7) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ReelplayTheme.black)
                    .frame(width: 35, height: 10)
                    .offset(x: 28)
                    .rotationEffect(.degrees(Double(index) * 28 - 84))
            }
        }
        .rotationEffect(.degrees(-4))
        .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
    }
}

private struct ReelDetailView: View {
    let reel: ReelItem
    let isBookmarked: Bool
    let isPubliclyShared: Bool
    let onToggleBookmark: () async -> Void
    let onTogglePublicShare: () async -> Void
    let onShareWithFriend: (String) async -> Void
    let onDelete: (ReelItem) async -> Void

    var body: some View {
        ReelSummaryView(
            reel: self.reel,
            isBookmarked: self.isBookmarked,
            isPubliclyShared: self.isPubliclyShared,
            onToggleBookmark: self.onToggleBookmark,
            onTogglePublicShare: self.onTogglePublicShare,
            onShareWithFriend: self.onShareWithFriend,
            onDelete: self.onDelete
        )
            .toolbar(.hidden, for: .navigationBar)
            .background(InteractivePopGestureEnabler())
    }
}

private struct ReelReferenceDetailView: View {
    let reel: ReelItem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var focusedSegmentID: UUID?
    @State private var autoplay = true

    private var segments: [ReelSegment] {
        self.reel.playbackSegments
    }

    var body: some View {
        ZStack(alignment: .top) {
            ReelplayTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    self.hero

                    VStack(alignment: .leading, spacing: 16) {
                        self.tabs

                        if self.selectedTab == 0 {
                            self.stepsHeader
                            VStack(spacing: 10) {
                                ForEach(Array(self.segments.enumerated()), id: \.element.id) { index, segment in
                                    DetailStepRow(
                                        reel: self.reel,
                                        segment: segment,
                                        index: index,
                                        isFocused: self.focusedSegmentID == segment.id
                                    )
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                            self.focusedSegmentID = self.focusedSegmentID == segment.id ? nil : segment.id
                                        }
                                    }
                                }
                            }
                        } else if self.selectedTab == 1 {
                            Text(self.reel.summary ?? self.reel.caption ?? "No details available yet.")
                                .font(.subheadline)
                                .foregroundStyle(ReelplayTheme.black.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No comments imported for this reel.")
                                .font(.subheadline)
                                .foregroundStyle(ReelplayTheme.mutedText)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                    .background(ReelplayTheme.background)
                    .clipShape(.rect(topLeadingRadius: 18, topTrailingRadius: 18))
                    .offset(y: -18)
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Button {
                    self.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ReelplayTheme.black)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.78))
                        .clipShape(Circle())
                }

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "bookmark")
                    Image(systemName: "ellipsis")
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ReelplayTheme.black)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.white.opacity(0.78))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, UIApplication.shared.reelplayTopSafeArea + 8)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                ReelThumbnailPlaceholder()
            }
            .frame(height: 286)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(self.reel.displayTitle)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(self.reel.source.capitalized, systemImage: self.reel.source.lowercased() == "tiktok" ? "music.note" : "camera")
                    Text(self.reel.displayCreator)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .frame(height: 286)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(self.tabTitles.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        self.selectedTab = index
                    }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(self.selectedTab == index ? .bold : .medium))
                        .foregroundStyle(self.selectedTab == index ? ReelplayTheme.black : ReelplayTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(self.selectedTab == index ? ReelplayTheme.black : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stepsHeader: some View {
        HStack {
            Text("\(self.segments.count) Steps")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ReelplayTheme.black)
            Text("•")
                .foregroundStyle(ReelplayTheme.mutedText)
            Text("\(SegmentPageView.format(self.reel.durationSeconds ?? self.segments.last?.endSeconds ?? 0)) total")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ReelplayTheme.mutedText)

            Spacer()

            Text("Auto-play")
                .font(.caption.weight(.medium))
                .foregroundStyle(ReelplayTheme.black.opacity(0.62))
            Toggle("", isOn: self.$autoplay)
                .labelsHidden()
                .scaleEffect(0.72)
        }
    }

    private var tabTitles: [String] {
        [
            "Steps",
            "Details",
            "Comments (\((self.reel.ocrEntries ?? []).count))",
        ]
    }
}

private struct DetailStepRow: View {
    let reel: ReelItem
    let segment: ReelSegment
    let index: Int
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(self.index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(ReelplayTheme.black.opacity(0.72))
                .frame(width: 24, height: 24)
                .background(ReelplayTheme.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(ReelplayTheme.divider))

            ReelThumbnailBadge(reel: self.reel, width: 76, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(self.segment.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                    .lineLimit(1)

                Text(self.segment.description.isEmpty ? self.segment.timeRangeText : self.segment.description)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReelplayTheme.black.opacity(0.56))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: self.isFocused ? "pause.circle.fill" : "checkmark")
                .font(.system(size: self.isFocused ? 32 : 16, weight: .bold))
                .foregroundStyle(self.isFocused ? ReelplayTheme.black : ReelplayTheme.black.opacity(0.54))
                .frame(width: 36, height: 36)
        }
        .padding(10)
        .background(self.isFocused ? ReelplayTheme.surface : ReelplayTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.isFocused ? ReelplayTheme.divider : .clear))
    }
}

private struct ReelSummaryView: View {
    let reel: ReelItem
    let isBookmarked: Bool
    let isPubliclyShared: Bool
    let onToggleBookmark: () async -> Void
    let onTogglePublicShare: () async -> Void
    let onShareWithFriend: (String) async -> Void
    let onDelete: (ReelItem) async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var playback: SegmentPlaybackController
    @State private var selectedTab = 0
    @State private var expandedSegmentID: UUID?
    @State private var focusedSegmentID: UUID?
    @State private var isShowingFullscreenVideo = false
    @State private var expandDragTranslation: CGFloat = 0
    @State private var canExpandFromCurrentDrag = false
    @State private var fullscreenCollapseProgress: CGFloat = 0
    @State private var contentOffsetY: CGFloat = 0
    @State private var contentRestingTopY: CGFloat?
    @State private var dragSessionStarted = false
    @State private var lockedCanExpandForThisDrag = false
    @State private var isTopPullArmed = true
    @State private var topPullArmTask: Task<Void, Never>?
    @State private var isShowingDownloadSheet = false
    @State private var isShowingMoreSheet = false
    @State private var isDeleting = false
    @State private var downloadState: ReelDownloadState = .idle
    @State private var downloadError: String?

    init(
        reel: ReelItem,
        isBookmarked: Bool,
        isPubliclyShared: Bool,
        onToggleBookmark: @escaping () async -> Void,
        onTogglePublicShare: @escaping () async -> Void,
        onShareWithFriend: @escaping (String) async -> Void,
        onDelete: @escaping (ReelItem) async -> Void
    ) {
        self.reel = reel
        self.isBookmarked = isBookmarked
        self.isPubliclyShared = isPubliclyShared
        self.onToggleBookmark = onToggleBookmark
        self.onTogglePublicShare = onTogglePublicShare
        self.onShareWithFriend = onShareWithFriend
        self.onDelete = onDelete
        self._playback = StateObject(wrappedValue: SegmentPlaybackController(videoURL: reel.videoURL, initialDurationSeconds: reel.durationSeconds))
    }

    private var segments: [ReelSegment] {
        self.reel.playbackSegments
    }

    private var expandedSegment: ReelSegment? {
        guard let expandedSegmentID else { return nil }
        return self.segments.first { $0.id == expandedSegmentID }
    }

    private var downloadSegment: ReelSegment? {
        if let focusedSegmentID,
           let focused = self.segments.first(where: { $0.id == focusedSegmentID }) {
            return focused
        }

        if let expandedSegment {
            return expandedSegment
        }

        return self.segments.first
    }

    private var heroHeight: CGFloat { 372 }

    var body: some View {
        ZStack {
            Color(hex: 0x0F0F10)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ReelSummaryScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("ReelSummaryScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(self.reel.title ?? self.reel.caption ?? "Saved reel")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Text(self.reel.creatorUsername.map { "@\($0)" } ?? self.reel.source.capitalized)
                                Text("•")
                                Text(self.reel.source.capitalized)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.48))
                        }

                        Spacer()

                        Button {
                            Task { await self.onToggleBookmark() }
                        } label: {
                            Image(systemName: self.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)

                    Picker("", selection: self.$selectedTab) {
                        Text("Steps").tag(0)
                        Text("Details").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    if self.selectedTab == 0 {
                        VStack(spacing: 0) {
                            ForEach(self.segments) { segment in
                                SegmentSummaryRow(
                                    reel: self.reel,
                                    segment: segment,
                                    isFocused: self.focusedSegmentID == segment.id,
                                    isExpanded: self.expandedSegmentID == segment.id,
                                    shouldLoadThumbnail: self.playback.canLoadSecondaryAssets,
                                    previousTitle: self.previousSegment(for: segment)?.title,
                                    nextTitle: self.nextSegment(for: segment)?.title,
                                    onPlaySegmentVideo: { self.openSegmentVideo(segment) },
                                    onSelectSegment: { self.selectSegment(segment) },
                                    onToggleExpanded: { self.toggleSegment(segment) },
                                    onPrevious: { self.selectAdjacentSegment(from: segment, direction: -1) },
                                    onNext: { self.selectAdjacentSegment(from: segment, direction: 1) }
                                )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text(self.reel.summary ?? self.reel.caption ?? "No summary yet.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, self.attachedContentTopHeight)
                .padding(.bottom, 30)
            }
            .coordinateSpace(name: "ReelSummaryScroll")
            .scrollIndicators(.hidden)
            .scrollDisabled(self.expandDragTranslation > 0 || self.isShowingFullscreenVideo)
            .reelplayScrollOffsetReader(
                offsetY: self.$contentOffsetY,
                restingTopY: self.$contentRestingTopY
            )
            .onPreferenceChange(ReelSummaryScrollOffsetPreferenceKey.self) { offset in
                guard #unavailable(iOS 18.0) else { return }
                if self.contentRestingTopY == nil || offset > (self.contentRestingTopY ?? offset) {
                    self.contentRestingTopY = offset
                }
                self.contentOffsetY = max(0, (self.contentRestingTopY ?? offset) - offset)
            }
            .onChange(of: self.contentOffsetY) { _, offset in
                self.updateTopPullArming(for: offset)
            }
            .simultaneousGesture(self.expandFromContentSwipe())

            VStack(spacing: 0) {
                ReelSummaryHero(
                    reel: self.reel,
                    player: self.playback.player,
                    currentSeconds: self.playback.currentSeconds,
                    durationSeconds: self.playback.durationSeconds ?? Double(self.reel.durationSeconds ?? 0),
                    isPlaying: self.playback.isPlaying,
                    expandProgress: self.expandDragProgress,
                    activeSegment: self.focusedSegmentID.flatMap { id in self.segments.first { $0.id == id } } ?? self.segments.first,
                    onSeek: { self.playback.seek(to: $0) },
                    onTogglePlayPause: { self.playback.togglePlayPause() },
                    onOpenFullscreen: { self.openFullscreenVideo() }
                )
                .frame(height: self.interactiveHeroHeight)
                .contentShape(Rectangle())
                .simultaneousGesture(self.expandVideoSwipe())
                .shadow(color: .black.opacity(self.expandDragProgress * 0.22), radius: 26 * self.expandDragProgress, y: 16 * self.expandDragProgress)

                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            VStack {
                HStack {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.34))
                            .clipShape(Circle())
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            self.isShowingDownloadSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 26, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(self.reel.videoURL == nil || self.downloadState.isWorking)

                        Button {
                            self.isShowingMoreSheet = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 26, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(self.isDeleting)
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.black.opacity(0.34))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, UIApplication.shared.reelplayTopSafeArea + 8)

                Spacer()
            }

            if self.isShowingFullscreenVideo {
                ReelFullscreenVideoView(
                    player: self.playback.player,
                    currentSeconds: self.playback.currentSeconds,
                    durationSeconds: self.playback.durationSeconds ?? Double(self.reel.durationSeconds ?? 0),
                    isPlaying: self.playback.isPlaying,
                    pinnedHeight: self.heroHeight,
                    onSeek: { self.playback.seek(to: $0) },
                    onTogglePlayPause: { self.playback.togglePlayPause() },
                    onDismiss: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            self.isShowingFullscreenVideo = false
                            self.fullscreenCollapseProgress = 0
                        }
                    },
                    onCollapseProgress: { progress in
                        self.fullscreenCollapseProgress = progress
                    },
                    onCollapseToPinned: {
                        self.isShowingFullscreenVideo = false
                        self.fullscreenCollapseProgress = 0
                    }
                )
                .zIndex(30)
            }

            if self.isShowingDownloadSheet {
                ReelDownloadSheet(
                    reel: self.reel,
                    segment: self.downloadSegment,
                    state: self.downloadState,
                    errorMessage: self.downloadError,
                    onDownloadFullVideo: { Task { await self.download(.fullVideo) } },
                    onDownloadSegment: { Task { await self.download(.segment) } },
                    onDismiss: {
                        guard !self.downloadState.isWorking else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            self.isShowingDownloadSheet = false
                            self.downloadState = .idle
                            self.downloadError = nil
                        }
                    }
                )
                .zIndex(40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if self.isShowingMoreSheet {
                ReelMoreSheet(
                    reel: self.reel,
                    isBookmarked: self.isBookmarked,
                    isPubliclyShared: self.isPubliclyShared,
                    isDeleting: self.isDeleting,
                    onToggleBookmark: { Task { await self.onToggleBookmark() } },
                    onTogglePublicShare: { Task { await self.onTogglePublicShare() } },
                    onShareWithFriend: { handle in Task { await self.onShareWithFriend(handle) } },
                    onOpenOriginal: {
                        self.openURL(self.reel.sourceURL)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            self.isShowingMoreSheet = false
                        }
                    },
                    onDelete: { Task { await self.deleteCurrentReel() } },
                    onDismiss: {
                        guard !self.isDeleting else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            self.isShowingMoreSheet = false
                        }
                    }
                )
                .zIndex(40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(hex: 0x0F0F10))
        .onAppear {
            Task {
                await self.playback.prepareAndPlayNormally()
            }
        }
        .onChange(of: self.focusedSegmentID) { _, _ in
            Task {
                if let focusedSegmentID,
                   let focusedSegment = self.segments.first(where: { $0.id == focusedSegmentID }) {
                    await self.playback.prepareAndPlay(focusedSegment)
                } else {
                    await self.playback.prepareAndPlayNormally()
                }
            }
        }
        .onDisappear {
            self.topPullArmTask?.cancel()
            guard !self.isShowingFullscreenVideo else { return }
            self.playback.pause()
        }
    }

    private var expandDragProgress: CGFloat {
        min(max(self.expandDragTranslation / 260, 0), 1)
    }

    private var interactiveHeroHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return self.heroHeight + (screenHeight - self.heroHeight) * self.expandDragProgress
    }

    private var attachedContentTopHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if self.isShowingFullscreenVideo {
            return screenHeight - ((screenHeight - self.heroHeight) * self.fullscreenCollapseProgress)
        }

        return self.interactiveHeroHeight
    }

    private var isContentScrolledToTop: Bool {
        self.contentOffsetY <= 1
    }

    private func deleteCurrentReel() async {
        guard !self.isDeleting else { return }
        self.isDeleting = true
        await self.onDelete(self.reel)
        self.isDeleting = false
        self.isShowingMoreSheet = false
        self.dismiss()
    }

    private func download(_ option: ReelDownloadOption) async {
        guard !self.downloadState.isWorking else { return }
        guard let videoURL = self.reel.videoURL else {
            self.downloadError = "This reel does not have a downloadable video."
            self.downloadState = .failed
            return
        }

        do {
            self.downloadError = nil
            self.downloadState = option == .fullVideo ? .downloadingFullVideo : .downloadingSegment

            switch option {
                case .fullVideo:
                    try await ReelVideoDownloadManager().saveFullVideo(from: videoURL)
                case .segment:
                    guard let segment = self.downloadSegment else {
                        throw ReelVideoDownloadManager.DownloadError.missingSegment
                    }
                    try await ReelVideoDownloadManager().saveSegment(from: videoURL, segment: segment)
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                self.downloadState = .saved
            }
            💥Feedback.success()
        } catch {
            self.downloadError = error.localizedDescription
            self.downloadState = .failed
            💥Feedback.error()
        }
    }

    private func expandVideoSwipe() -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.2
                let draggingDown = value.translation.height > 0
                guard mostlyVertical, draggingDown else { return }
                self.expandDragTranslation = max(0, value.translation.height)
            }
            .onEnded { value in
                let movedDown = value.translation.height > 72 || value.predictedEndTranslation.height > 140
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.35
                if movedDown, mostlyVertical {
                    self.completeDragToFullscreen()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.expandDragTranslation = 0
                    }
                }
            }
    }

    private func expandFromContentSwipe() -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                self.startExpandDragIfNeeded()
                guard self.canStartOrContinueExpandDrag(value) else { return }
                self.expandDragTranslation = max(0, value.translation.height)
            }
            .onEnded { value in
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.35
                let movedDown = value.translation.height > 72 || value.predictedEndTranslation.height > 140
                let canComplete = self.canExpandFromCurrentDrag && self.lockedCanExpandForThisDrag && mostlyVertical
                self.resetExpandDragSession()
                guard canComplete else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.expandDragTranslation = 0
                    }
                    return
                }

                if movedDown {
                    self.completeDragToFullscreen()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.expandDragTranslation = 0
                    }
                }
            }
    }

    private func startExpandDragIfNeeded() {
        guard !self.dragSessionStarted else { return }
        self.dragSessionStarted = true
        self.lockedCanExpandForThisDrag = self.isContentScrolledToTop && self.isTopPullArmed
        self.canExpandFromCurrentDrag = self.lockedCanExpandForThisDrag
    }

    private func canStartOrContinueExpandDrag(_ value: DragGesture.Value) -> Bool {
        let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.2
        let draggingDown = value.translation.height > 0
        guard mostlyVertical, draggingDown else {
            if self.expandDragTranslation == 0 {
                self.canExpandFromCurrentDrag = false
            }
            return false
        }

        return self.lockedCanExpandForThisDrag && self.canExpandFromCurrentDrag
    }

    private func resetExpandDragSession() {
        self.canExpandFromCurrentDrag = false
        self.lockedCanExpandForThisDrag = false
        self.dragSessionStarted = false

        if self.isContentScrolledToTop, !self.isTopPullArmed {
            self.scheduleTopPullRearm()
        }
    }

    private func updateTopPullArming(for offset: CGFloat) {
        if offset > 1 {
            self.topPullArmTask?.cancel()
            self.topPullArmTask = nil
            self.isTopPullArmed = false
            return
        }

        guard !self.dragSessionStarted, !self.isTopPullArmed else { return }
        self.scheduleTopPullRearm()
    }

    private func scheduleTopPullRearm() {
        guard self.topPullArmTask == nil else { return }

        self.topPullArmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self.isTopPullArmed = self.isContentScrolledToTop && !self.dragSessionStarted
            self.topPullArmTask = nil
        }
    }

    private func completeDragToFullscreen() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.92)) {
            self.expandDragTranslation = 260
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                self.isShowingFullscreenVideo = true
                self.expandDragTranslation = 0
            }
        }
    }

    private func toggleSegment(_ segment: ReelSegment) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if self.expandedSegmentID == segment.id {
                self.expandedSegmentID = nil
                if self.focusedSegmentID == segment.id {
                    self.focusedSegmentID = nil
                }
            } else {
                self.expandedSegmentID = segment.id
                self.focusedSegmentID = segment.id
            }
        }
        💥Feedback.selection()
    }

    private func selectSegment(_ segment: ReelSegment) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            self.focusedSegmentID = self.focusedSegmentID == segment.id ? nil : segment.id
        }
        💥Feedback.selection()
    }

    private func previousSegment(for segment: ReelSegment) -> ReelSegment? {
        guard let index = self.segments.firstIndex(where: { $0.id == segment.id }),
              index > 0 else {
            return nil
        }
        return self.segments[index - 1]
    }

    private func nextSegment(for segment: ReelSegment) -> ReelSegment? {
        guard let index = self.segments.firstIndex(where: { $0.id == segment.id }),
              index < self.segments.count - 1 else {
            return nil
        }
        return self.segments[index + 1]
    }

    private func selectAdjacentSegment(from segment: ReelSegment, direction: Int) {
        guard let index = self.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let nextIndex = index + direction
        guard self.segments.indices.contains(nextIndex) else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            self.expandedSegmentID = self.segments[nextIndex].id
            self.focusedSegmentID = self.segments[nextIndex].id
        }
    }

    private func openFullscreenVideo() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            self.isShowingFullscreenVideo = true
        }
    }

    private func openSegmentVideo(_ segment: ReelSegment) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            self.focusedSegmentID = segment.id
            self.isShowingFullscreenVideo = true
        }
        self.playback.play(segment)
        💥Feedback.selection()
    }
}

private struct ReelSummaryHero: View {
    let reel: ReelItem
    let player: AVPlayer?
    let currentSeconds: Double
    let durationSeconds: Double
    let isPlaying: Bool
    let expandProgress: CGFloat
    let activeSegment: ReelSegment?
    let onSeek: (Double) -> Void
    let onTogglePlayPause: () -> Void
    let onOpenFullscreen: () -> Void

    private var activeSlideItem: ReelMediaItem? {
        guard self.reel.videoURL == nil,
              let mediaItems = self.reel.mediaItems,
              !mediaItems.isEmpty,
              let segment = self.activeSegment else { return nil }
        let sorted = mediaItems.sorted { $0.orderIndex < $1.orderIndex }
        return sorted[min(segment.orderIndex, sorted.count - 1)]
    }

    private var slideImageURL: URL? {
        guard let item = self.activeSlideItem else { return nil }
        return item.thumbnailURL ?? (item.type == "image" ? item.url : nil)
    }

    private var slideVideoURL: URL? {
        guard let item = self.activeSlideItem, item.type == "video" else { return nil }
        return item.url
    }
    @State private var scrubSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var areControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Button(action: self.showControlsTemporarily) {
                GeometryReader { proxy in
                    ZStack {
                        Color.black

                        if let player {
                            FullScreenReelVideoPlayer(player: player, videoGravity: .resizeAspect)
                                .frame(width: self.videoFrameWidth(in: proxy.size), height: self.videoFrameHeight(in: proxy.size))
                                .clipShape(RoundedRectangle(cornerRadius: self.videoCornerRadius))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        } else if let videoURL = self.slideVideoURL {
                            SlideVideoPlayer(url: videoURL, thumbnailURL: self.slideImageURL)
                                .frame(width: self.videoFrameWidth(in: proxy.size), height: self.videoFrameHeight(in: proxy.size))
                                .clipShape(RoundedRectangle(cornerRadius: self.videoCornerRadius))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .id(videoURL.absoluteString)
                        } else {
                            let isSlide = self.reel.videoURL == nil && !(self.reel.mediaItems ?? []).isEmpty
                            ZStack {
                                CachedRemoteImage(url: self.reel.displayThumbnailURL) { Color.black }
                                    .blur(radius: 20)
                                    .opacity(0.5)
                                CachedRemoteImage(
                                    url: self.slideImageURL ?? self.reel.displayThumbnailURL,
                                    contentMode: isSlide ? .fit : .fill
                                ) { Color.clear }
                            }
                            .frame(width: self.videoFrameWidth(in: proxy.size), height: self.videoFrameHeight(in: proxy.size))
                            .clipShape(RoundedRectangle(cornerRadius: self.videoCornerRadius))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            LinearGradient(
                colors: [.black.opacity(0.12), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(1 - min(self.expandProgress, 0.9))

            VStack {
                Spacer()

                VStack(spacing: 8) {
                    HStack {
                        Spacer()

                        Button(action: self.onOpenFullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.42))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        if self.areControlsVisible {
                            Button {
                                self.showControlsTemporarily()
                                self.onTogglePlayPause()
                            } label: {
                                Image(systemName: self.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.16))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Text("\(SegmentPageView.format(Int(self.displaySeconds))) / \(SegmentPageView.format(Int(self.safeDuration)))")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .transition(.opacity)
                        }

                        Spacer()
                    }

                    if self.areControlsVisible {
                        ReelVideoScrubber(
                            value: self.$scrubSeconds,
                            duration: self.safeDuration,
                            onEditingChanged: { editing in
                                self.isScrubbing = editing
                                if editing {
                                    self.showControls()
                                } else {
                                    self.onSeek(self.scrubSeconds)
                                    self.scheduleControlsHide()
                                }
                            }
                        )
                        .frame(height: 22)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
            .opacity(1 - self.expandProgress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .contentShape(Rectangle())
        .onTapGesture {
            self.showControlsTemporarily()
        }
        .onAppear {
            self.scrubSeconds = self.currentSeconds
            self.showControlsTemporarily()
        }
        .onChange(of: self.currentSeconds) { _, seconds in
            guard !self.isScrubbing else { return }
            self.scrubSeconds = min(max(0, seconds), self.safeDuration)
        }
        .onDisappear {
            self.hideControlsTask?.cancel()
        }
    }

    private var safeDuration: Double {
        max(1, self.durationSeconds)
    }

    private var displaySeconds: Double {
        self.isScrubbing ? self.scrubSeconds : self.currentSeconds
    }

    private func videoFrameWidth(in size: CGSize) -> CGFloat {
        let pinnedWidth = min(size.width, self.pinnedVideoHeight(in: size) * 9 / 16)
        return pinnedWidth + ((size.width - pinnedWidth) * self.expandProgress)
    }

    private func videoFrameHeight(in size: CGSize) -> CGFloat {
        let pinnedHeight = self.pinnedVideoHeight(in: size)
        return pinnedHeight + ((size.height - pinnedHeight) * self.expandProgress)
    }

    private func pinnedVideoHeight(in size: CGSize) -> CGFloat {
        let topInset = UIApplication.shared.reelplayTopSafeArea + 14
        return max(1, size.height - topInset)
    }

    private var videoCornerRadius: CGFloat {
        18 * (1 - self.expandProgress)
    }

    private func showControls() {
        self.hideControlsTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            self.areControlsVisible = true
        }
    }

    private func showControlsTemporarily() {
        self.showControls()
        self.scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        self.hideControlsTask?.cancel()
        self.hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !self.isScrubbing else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.areControlsVisible = false
                }
            }
        }
    }
}

private struct ReelVideoScrubber: View {
    @Binding var value: Double
    let duration: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let progress = self.duration <= 0 ? 0 : min(max(self.value / self.duration, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(height: 4)

                Capsule()
                    .fill(.white)
                    .frame(width: max(8, proxy.size.width * progress), height: 4)

                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
                    .offset(x: max(0, min(proxy.size.width - 13, proxy.size.width * progress - 6.5)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        self.onEditingChanged(true)
                        let x = min(max(0, drag.location.x), proxy.size.width)
                        self.value = self.duration * x / max(1, proxy.size.width)
                    }
                    .onEnded { drag in
                        let x = min(max(0, drag.location.x), proxy.size.width)
                        self.value = self.duration * x / max(1, proxy.size.width)
                        self.onEditingChanged(false)
                    }
            )
        }
    }
}

private struct SegmentSummaryRow: View {
    let reel: ReelItem
    let segment: ReelSegment
    let isFocused: Bool
    let isExpanded: Bool
    let shouldLoadThumbnail: Bool
    let previousTitle: String?
    let nextTitle: String?
    let onPlaySegmentVideo: () -> Void
    let onSelectSegment: () -> Void
    let onToggleExpanded: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: self.onPlaySegmentVideo) {
                    SegmentThumbnail(
                        reel: self.reel,
                        segment: self.segment,
                        shouldLoadThumbnail: self.shouldLoadThumbnail
                    )
                }
                .buttonStyle(.plain)

                Button(action: self.onSelectSegment) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(self.segment.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(self.isFocused ? ReelplayTheme.accent : .white)
                            .lineLimit(2)

                        Text(self.segment.description.isEmpty ? "View AI summary" : self.segment.description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(self.isFocused ? 0.78 : 0.56))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: self.onToggleExpanded) {
                    Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(self.isFocused ? ReelplayTheme.black : .white.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(self.isFocused ? ReelplayTheme.accent : .white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(self.isExpanded ? "Collapse segment" : "Expand segment")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                if self.isFocused {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ReelplayTheme.accent)
                                .frame(width: 4)
                                .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
            }

            if self.isExpanded {
                SegmentExpandedSummary(
                    segment: self.segment,
                    previousTitle: self.previousTitle,
                    nextTitle: self.nextTitle,
                    onPrevious: self.onPrevious,
                    onNext: self.onNext
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(self.isFocused ? ReelplayTheme.accent.opacity(0.24) : .white.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 112)
        }
    }
}

private struct SegmentExpandedSummary: View {
    let segment: ReelSegment
    let previousTitle: String?
    let nextTitle: String?
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(self.segment.description.isEmpty ? "No summary yet." : self.segment.description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rawText = self.segment.rawText, !rawText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Text(rawText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !self.segment.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    FlowLayout(items: self.segment.tags) { tag in
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            SegmentDetailPager(
                previousTitle: self.previousTitle,
                nextTitle: self.nextTitle,
                onPrevious: self.onPrevious,
                onNext: self.onNext
            )
        }
    }
}

private struct SegmentThumbnail: View {
    let reel: ReelItem
    let segment: ReelSegment
    let shouldLoadThumbnail: Bool

    private var slideImageURL: URL? {
        guard self.reel.videoURL == nil,
              let mediaItems = self.reel.mediaItems,
              !mediaItems.isEmpty else { return nil }
        let sorted = mediaItems.sorted { $0.orderIndex < $1.orderIndex }
        let item = sorted[min(self.segment.orderIndex, sorted.count - 1)]
        return item.thumbnailURL ?? (item.type == "image" ? item.url : nil)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SegmentFrameThumbnail(
                videoURL: self.reel.videoURL,
                fallbackURL: self.slideImageURL ?? self.reel.displayThumbnailURL,
                seconds: self.segment.startSeconds,
                shouldLoad: self.shouldLoadThumbnail
            )
            .frame(width: 82, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(SegmentPageView.format(self.segment.startSeconds))
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(5)
        }
    }
}

private struct SegmentFrameThumbnail: View {
    let videoURL: URL?
    let fallbackURL: URL?
    let seconds: Int
    let shouldLoad: Bool
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !self.shouldLoad {
                SegmentDeferredThumbnailPlaceholder()
            } else if self.didFail {
                CachedRemoteImage(url: self.fallbackURL) {
                    ReelThumbnailPlaceholder()
                }
            } else {
                SegmentThumbnailLoadingPlaceholder(fallbackURL: self.fallbackURL)
            }
        }
        .clipped()
        .task(id: self.taskID) {
            await self.loadFrame()
        }
    }

    private var taskID: String {
        "\(self.videoURL?.absoluteString ?? "missing")-\(self.seconds)-\(self.shouldLoad)"
    }

    @MainActor
    private func loadFrame() async {
        self.didFail = false

        guard self.shouldLoad else { return }

        let cacheKey = self.frameCacheKey
        if let cached = ReelplayImageCache.shared.image(for: cacheKey) {
            self.image = cached
            return
        }

        self.image = nil

        guard let videoURL else {
            self.didFail = true
            return
        }

        do {
            let thumbnail = try await Self.extractFrame(from: videoURL, at: self.seconds)
            ReelplayImageCache.shared.set(thumbnail, for: cacheKey)
            self.image = thumbnail
        } catch {
            self.didFail = true
        }
    }

    private var frameCacheKey: String {
        "segment-frame:\(self.videoURL?.absoluteString ?? "missing"):\(self.seconds)"
    }

    private static func extractFrame(from videoURL: URL, at seconds: Int) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 328, height: 256)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

            let time = CMTime(seconds: Double(max(0, seconds)), preferredTimescale: 600)
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: image)
        }.value
    }
}

private struct SegmentDeferredThumbnailPlaceholder: View {
    var body: some View {
        ZStack {
            Color(hex: 0x1C1C1E)

            Image("AboutAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .opacity(0.42)
        }
    }
}

private struct SegmentThumbnailLoadingPlaceholder: View {
    let fallbackURL: URL?

    var body: some View {
        ZStack {
            CachedRemoteImage(url: self.fallbackURL) {
                ReelThumbnailPlaceholder()
            }

            Color.black.opacity(0.24)

            ProgressView()
                .tint(.white)
                .scaleEffect(0.72)
        }
    }
}

private struct SegmentDetailView: View {
    let reel: ReelItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: SegmentPlaybackController
    @State private var activeSegmentID: UUID

    init(reel: ReelItem, initialSegment: ReelSegment) {
        self.reel = reel
        self._activeSegmentID = State(initialValue: initialSegment.id)
        self._playback = StateObject(wrappedValue: SegmentPlaybackController(videoURL: reel.videoURL))
    }

    private var segments: [ReelSegment] {
        self.reel.playbackSegments
    }

    private var activeSegment: ReelSegment {
        self.segments.first { $0.id == self.activeSegmentID } ?? self.segments[0]
    }

    private var activeIndex: Int {
        self.segments.firstIndex { $0.id == self.activeSegment.id } ?? 0
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0F0F10)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button {
                            self.dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }

                        Spacer()

                        Text("Step")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .padding(.top, UIApplication.shared.reelplayTopSafeArea + 8)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(Self.timestamp(self.activeSegment.startSeconds)) - \(Self.timestamp(self.activeSegment.endSeconds))")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white.opacity(0.92))

                        Text(self.activeSegment.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ZStack {
                        if let player = self.playback.player {
                            FullScreenReelVideoPlayer(player: player)
                        } else {
                            CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                                ReelThumbnailPlaceholder()
                            }
                        }

                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(height: 212)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Description")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(self.activeSegment.description.isEmpty ? "No summary yet." : self.activeSegment.description)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let rawText = self.activeSegment.rawText, !rawText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tips")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text(rawText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !self.activeSegment.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            FlowLayout(items: self.activeSegment.tags) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    SegmentDetailPager(
                        previousTitle: self.previousSegment?.title,
                        nextTitle: self.nextSegment?.title,
                        onPrevious: self.goPrevious,
                        onNext: self.goNext
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(hex: 0x0F0F10))
        .onAppear {
            self.playback.play(self.activeSegment)
        }
        .onChange(of: self.activeSegmentID) { _, _ in
            self.playback.play(self.activeSegment)
            💥Feedback.selection()
        }
        .onDisappear {
            self.playback.pause()
        }
    }

    private var previousSegment: ReelSegment? {
        guard self.activeIndex > 0 else { return nil }
        return self.segments[self.activeIndex - 1]
    }

    private var nextSegment: ReelSegment? {
        guard self.activeIndex < self.segments.count - 1 else { return nil }
        return self.segments[self.activeIndex + 1]
    }

    private func goPrevious() {
        guard let previousSegment else { return }
        self.activeSegmentID = previousSegment.id
    }

    private func goNext() {
        guard let nextSegment else { return }
        self.activeSegmentID = nextSegment.id
    }

    private static func timestamp(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
    }
}

private struct SegmentDetailPager: View {
    let previousTitle: String?
    let nextTitle: String?
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: self.onPrevious) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Previous")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.56))
                        Text(self.previousTitle ?? "None")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .disabled(self.previousTitle == nil)

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)

            Button(action: self.onNext) {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.56))
                        Text(self.nextTitle ?? "None")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
            }
            .disabled(self.nextTitle == nil)
        }
        .foregroundStyle(.white)
        .frame(height: 70)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReelFullscreenVideoView: View {
    let player: AVPlayer?
    let currentSeconds: Double
    let durationSeconds: Double
    let isPlaying: Bool
    let pinnedHeight: CGFloat
    let onSeek: (Double) -> Void
    let onTogglePlayPause: () -> Void
    let onDismiss: () -> Void
    let onCollapseProgress: (CGFloat) -> Void
    let onCollapseToPinned: () -> Void
    @State private var scrubSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var areControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var collapseDragTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                Button(action: self.showControlsTemporarily) {
                    ZStack {
                        Color.black

                        if let player {
                            FullScreenReelVideoPlayer(player: player)
                                .frame(
                                    width: self.videoFrameWidth(containerWidth: proxy.size.width),
                                    height: self.videoFrameHeight(containerHeight: UIScreen.main.bounds.height)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: self.videoCornerRadius))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(width: proxy.size.width, height: self.collapseHeight)
                }
                .buttonStyle(.plain)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .opacity(1 - self.collapseProgress)

            VStack {
                HStack {
                    Button {
                        self.onDismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.36))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, UIApplication.shared.reelplayTopSafeArea + 8)
                .opacity(1 - self.collapseProgress)

                Spacer()

                VStack(spacing: 9) {
                    HStack {
                        Button {
                            self.showControlsTemporarily()
                            self.onTogglePlayPause()
                        } label: {
                            Image(systemName: self.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        if self.areControlsVisible {
                            Text("\(SegmentPageView.format(Int(self.displaySeconds))) / \(SegmentPageView.format(Int(self.safeDuration)))")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                        }

                        Spacer()
                    }

                    if self.areControlsVisible {
                        ReelVideoScrubber(
                            value: self.$scrubSeconds,
                            duration: self.safeDuration,
                            onEditingChanged: { editing in
                                self.isScrubbing = editing
                                if editing {
                                    self.showControls()
                                } else {
                                    self.onSeek(self.scrubSeconds)
                                    self.scheduleControlsHide()
                                }
                            }
                        )
                        .frame(height: 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(24, UIApplication.shared.reelplayTopSafeArea == 0 ? 24 : 34))
                .opacity(1 - self.collapseProgress)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: self.collapseHeight, alignment: .top)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: self.collapseCornerRadius))
        .opacity(self.collapseOpacity)
        .onAppear {
            self.scrubSeconds = self.currentSeconds
            self.onCollapseProgress(0)
            self.showControlsTemporarily()
        }
        .onChange(of: self.collapseProgress) { _, progress in
            self.onCollapseProgress(progress)
        }
        .onChange(of: self.currentSeconds) { _, seconds in
            guard !self.isScrubbing else { return }
            self.scrubSeconds = min(max(0, seconds), self.safeDuration)
        }
        .onDisappear {
            self.hideControlsTask?.cancel()
            self.onCollapseProgress(0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            self.showControlsTemporarily()
        }
        .simultaneousGesture(self.collapseToPinnedSwipe())
    }

    private var safeDuration: Double {
        max(1, self.durationSeconds)
    }

    private var displaySeconds: Double {
        self.isScrubbing ? self.scrubSeconds : self.currentSeconds
    }

    private var collapseProgress: CGFloat {
        min(max(-self.collapseDragTranslation / 280, 0), 1)
    }

    private var collapseHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight - ((screenHeight - self.pinnedHeight) * self.collapseProgress)
    }

    private func videoFrameWidth(containerWidth: CGFloat) -> CGFloat {
        let pinnedReelWidth = min(containerWidth, self.pinnedVideoHeight * 9 / 16)
        return containerWidth - ((containerWidth - pinnedReelWidth) * self.collapseProgress)
    }

    private func videoFrameHeight(containerHeight: CGFloat) -> CGFloat {
        containerHeight - ((containerHeight - self.pinnedVideoHeight) * self.collapseProgress)
    }

    private var pinnedVideoHeight: CGFloat {
        let topInset = UIApplication.shared.reelplayTopSafeArea + 14
        return max(1, self.pinnedHeight - topInset)
    }

    private var videoCornerRadius: CGFloat {
        18 * self.collapseProgress
    }

    private var collapseCornerRadius: CGFloat {
        8 * self.collapseProgress
    }

    private var collapseOpacity: Double {
        1
    }

    private func collapseToPinnedSwipe() -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.2
                guard mostlyVertical else { return }
                self.collapseDragTranslation = min(0, value.translation.height)
            }
            .onEnded { value in
                let movedUp = value.translation.height < -72 || value.predictedEndTranslation.height < -140
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.35
                if movedUp, mostlyVertical {
                    self.completeDragToPinned()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.collapseDragTranslation = 0
                    }
                }
            }
    }

    private func completeDragToPinned() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.92)) {
            self.collapseDragTranslation = -280
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                self.collapseDragTranslation = 0
                self.onCollapseToPinned()
            }
        }
    }

    private func showControls() {
        self.hideControlsTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            self.areControlsVisible = true
        }
    }

    private func showControlsTemporarily() {
        self.showControls()
        self.scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        self.hideControlsTask?.cancel()
        self.hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !self.isScrubbing else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.areControlsVisible = false
                }
            }
        }
    }
}

private struct SegmentReelPlayerView: View {
    let reel: ReelItem
    let initialSegmentID: UUID?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: SegmentPlaybackController
    @State private var activeSegmentID: UUID?
    @State private var showDetails = false

    init(reel: ReelItem, initialSegmentID: UUID? = nil) {
        self.reel = reel
        self.initialSegmentID = initialSegmentID
        self._playback = StateObject(wrappedValue: SegmentPlaybackController(videoURL: reel.videoURL))
    }

    private var segments: [ReelSegment] {
        self.reel.playbackSegments
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(self.segments) { segment in
                            SegmentPageView(
                                reel: self.reel,
                                segment: segment,
                                player: self.playback.player,
                                isActive: self.activeSegmentID == segment.id,
                                showDetails: self.showDetails
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(segment.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: self.$activeSegmentID)
                .background(Color.black)
                .contentShape(Rectangle())
                .padding(.leading, 1)

                HStack {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.34))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Step")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            self.showDetails.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.34))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, max(proxy.safeAreaInsets.top, UIApplication.shared.reelplayTopSafeArea, 44) + 8)
            }
            .onAppear {
                let initialSegment = self.segments.first { $0.id == self.initialSegmentID } ?? self.segments.first
                if let segment = initialSegment, self.reel.videoURL != nil {
                    self.playback.play(segment)
                }
                DispatchQueue.main.async {
                    self.activeSegmentID = initialSegment?.id
                }
            }
            .onChange(of: self.activeSegmentID) { _, id in
                guard let id,
                      let segment = self.segments.first(where: { $0.id == id }) else {
                    return
                }

                if self.reel.videoURL != nil {
                    self.playback.play(segment)
                }
                💥Feedback.selection()
            }
            .onDisappear {
                self.playback.pause()
            }
            .simultaneousGesture(self.leftHalfBackSwipe(width: proxy.size.width))
        }
        .ignoresSafeArea()
        .background(InteractivePopGestureEnabler())
    }

    private func leftHalfBackSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let startedInLeftHalf = value.startLocation.x <= width * 0.5
                let movedRight = value.translation.width > 72
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4

                guard startedInLeftHalf, movedRight, mostlyHorizontal else { return }
                self.dismiss()
            }
    }
}

private extension ReelItem {
    var displayTitle: String {
        self.title ?? self.caption ?? "Saved reel"
    }

    var displayCreator: String {
        self.creatorUsername.map { "@\($0)" } ?? self.source.capitalized
    }

    var durationDisplayText: String {
        guard let seconds = self.durationSeconds else { return "--:--" }
        return SegmentPageView.format(seconds)
    }

    var displayThumbnailURL: URL? {
        self.mediaItems?
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.thumbnailURL ?? ($0.type == "image" ? $0.url : nil) }
            .first ?? self.thumbnailURL
    }

    var isMicroreelReady: Bool {
        return self.segments.count >= 2
    }

    var needsOCRProcessing: Bool {
        let retryableStatuses = ["needs_ocr", "ready_basic", "ocr_failed"]
        if retryableStatuses.contains(self.status) {
            return self.videoURL != nil || !(self.mediaItems ?? []).isEmpty
        }

        guard self.videoURL != nil else { return false }
        let hasOCR = !(self.ocrEntries ?? []).isEmpty
        return self.segments.count < 2 && !hasOCR
    }

    var playbackSegments: [ReelSegment] {
        if !self.segments.isEmpty {
            return self.segments.sorted { $0.orderIndex < $1.orderIndex }
        }

        return [
            ReelSegment(
                id: UUID(),
                startSeconds: 0,
                endSeconds: max(1, self.durationSeconds ?? 30),
                title: self.title ?? "Saved reel",
                description: self.summary ?? self.caption ?? "Replay this reel from the beginning.",
                rawText: self.caption,
                tags: [],
                orderIndex: 0
            ),
        ]
    }
}

private struct ReelSummaryScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReelplayScrollOffsetReader: ViewModifier {
    @Binding var offsetY: CGFloat
    @Binding var restingTopY: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    self.offsetY = max(0, newValue)
                }
        } else {
            content
                .coordinateSpace(name: "ReelSummaryScroll")
        }
    }
}

private extension View {
    func reelplayScrollOffsetReader(offsetY: Binding<CGFloat>, restingTopY: Binding<CGFloat?>) -> some View {
        self.modifier(ReelplayScrollOffsetReader(offsetY: offsetY, restingTopY: restingTopY))
    }
}

private extension ReelSegment {
    var timeRangeText: String {
        "\(SegmentPageView.format(self.startSeconds)) - \(SegmentPageView.format(self.endSeconds))"
    }
}

private extension UIApplication {
    var reelplayTopSafeArea: CGFloat {
        self.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    var reelplayBottomSafeArea: CGFloat {
        self.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

private struct SegmentPageView: View {
    let reel: ReelItem
    let segment: ReelSegment
    let player: AVPlayer?
    let isActive: Bool
    let showDetails: Bool

    private var slideItem: ReelMediaItem? {
        guard self.reel.videoURL == nil,
              let mediaItems = self.reel.mediaItems,
              !mediaItems.isEmpty else { return nil }
        let sorted = mediaItems.sorted { $0.orderIndex < $1.orderIndex }
        return sorted[min(self.segment.orderIndex, sorted.count - 1)]
    }

    private var slideImageURL: URL? {
        guard let item = self.slideItem else { return nil }
        return item.thumbnailURL ?? (item.type == "image" ? item.url : nil)
    }

    private var slideVideoURL: URL? {
        guard let item = self.slideItem, item.type == "video" else { return nil }
        return item.url
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if self.isActive, let player {
                FullScreenReelVideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if self.isActive, let videoURL = self.slideVideoURL {
                SlideVideoPlayer(url: videoURL, thumbnailURL: self.slideImageURL)
                    .ignoresSafeArea()
            } else {
                let isSlide = self.reel.videoURL == nil && !(self.reel.mediaItems ?? []).isEmpty
                ZStack {
                    CachedRemoteImage(url: self.reel.displayThumbnailURL) { Color.black }
                        .ignoresSafeArea()
                        .blur(radius: 24)
                        .opacity(0.55)
                    CachedRemoteImage(
                        url: self.slideImageURL ?? self.reel.displayThumbnailURL,
                        contentMode: isSlide ? .fit : .fill
                    ) { Color.clear }
                        .ignoresSafeArea()
                }
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [.black.opacity(0.36), .clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Spacer()

                Text("\(Self.format(self.segment.startSeconds)) - \(Self.format(self.segment.endSeconds))")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Text(self.segment.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !self.segment.description.isEmpty {
                    Text(self.segment.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(self.showDetails ? 8 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if self.showDetails {
                    VStack(alignment: .leading, spacing: 10) {
                        if !self.segment.tags.isEmpty {
                            FlowLayout(items: self.segment.tags) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.white.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }

                        if let rawText = self.segment.rawText, !rawText.isEmpty {
                            Text(rawText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(5)
                        }
                    }
                    .padding(.top, 4)
                }

                HStack {
                    if let creator = self.reel.creatorUsername {
                        Text("@\(creator)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()

                    Image(systemName: "repeat")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Auto replay")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 42)
        }
    }

    static func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

private struct SlideVideoPlayer: View {
    let url: URL
    let thumbnailURL: URL?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            CachedRemoteImage(url: self.thumbnailURL) { Color.black }
            if let player {
                FullScreenReelVideoPlayer(player: player)
            }
        }
        .onAppear {
            let p = AVPlayer(url: self.url)
            p.automaticallyWaitsToMinimizeStalling = false
            p.currentItem?.preferredForwardBufferDuration = 2
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { _ in
                p.seek(to: .zero)
                p.play()
            }
            p.play()
            self.player = p
        }
        .onDisappear {
            self.player?.pause()
            self.player = nil
        }
    }
}

private struct FullScreenReelVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = self.player
        view.playerLayer.videoGravity = self.videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = self.player
        uiView.playerLayer.videoGravity = self.videoGravity
    }
}

private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        self.layer as! AVPlayerLayer
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? Controller)?.enablePopGesture()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            self.enablePopGesture()
        }

        func enablePopGesture() {
            guard let navigationController = self.navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

private enum ReelDownloadOption {
    case fullVideo
    case segment
}

private enum ReelDownloadState: Equatable {
    case idle
    case downloadingFullVideo
    case downloadingSegment
    case saved
    case failed

    var isWorking: Bool {
        switch self {
            case .downloadingFullVideo, .downloadingSegment:
                true
            case .idle, .saved, .failed:
                false
        }
    }

    var statusText: String {
        switch self {
            case .idle:
                "Choose what to save"
            case .downloadingFullVideo:
                "Saving full reel..."
            case .downloadingSegment:
                "Exporting selected segment..."
            case .saved:
                "Saved to Photos"
            case .failed:
                "Could not save video"
        }
    }
}

private struct ReelDownloadSheet: View {
    let reel: ReelItem
    let segment: ReelSegment?
    let state: ReelDownloadState
    let errorMessage: String?
    let onDownloadFullVideo: () -> Void
    let onDownloadSegment: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: self.onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                        ReelThumbnailPlaceholder()
                    }
                    .frame(width: 58, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download Reel")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)

                        Text(self.state.statusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.58))
                    }

                    Spacer()

                    Button(action: self.onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)
                            .frame(width: 34, height: 34)
                            .background(ReelplayTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.state.isWorking)
                }

                if self.state.isWorking {
                    ProgressView()
                        .tint(ReelplayTheme.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }

                VStack(spacing: 10) {
                    ReelDownloadChoiceButton(
                        title: "Full video",
                        subtitle: "Save the entire reel to Photos",
                        symbol: "rectangle.portrait.and.arrow.right",
                        isDisabled: self.state.isWorking || self.reel.videoURL == nil,
                        action: self.onDownloadFullVideo
                    )

                    ReelDownloadChoiceButton(
                        title: "Selected segment only",
                        subtitle: self.segment?.timeRangeText ?? "Select a segment first",
                        symbol: "scissors",
                        isDisabled: self.state.isWorking || self.segment == nil || self.reel.videoURL == nil,
                        action: self.onDownloadSegment
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, max(12, UIApplication.shared.reelplayBottomSafeArea + 12))
            .background(ReelplayTheme.background)
            .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
            .shadow(color: .black.opacity(0.18), radius: 28, y: -10)
            .padding(.bottom, -UIApplication.shared.reelplayBottomSafeArea)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct ReelDownloadChoiceButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 13) {
                Image(systemName: self.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(ReelplayTheme.black)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    Text(self.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ReelplayTheme.black.opacity(0.38))
            }
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ReelplayTheme.divider.opacity(0.9)))
            .opacity(self.isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(self.isDisabled)
    }
}

private struct ReelMoreSheet: View {
    let reel: ReelItem
    let isBookmarked: Bool
    let isPubliclyShared: Bool
    let isDeleting: Bool
    let onToggleBookmark: () -> Void
    let onTogglePublicShare: () -> Void
    let onShareWithFriend: (String) -> Void
    let onOpenOriginal: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void
    @State private var friendHandle = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: self.onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    CachedRemoteImage(url: self.reel.displayThumbnailURL) {
                        ReelThumbnailPlaceholder()
                    }
                    .frame(width: 58, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reel Options")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)

                        Text(self.reel.sourceURL.host(percentEncoded: false) ?? self.reel.source.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.58))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: self.onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ReelplayTheme.black)
                            .frame(width: 34, height: 34)
                            .background(ReelplayTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.isDeleting)
                }

                if self.isDeleting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(ReelplayTheme.black)
                        Text("Deleting reel...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ReelplayTheme.black.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                VStack(spacing: 10) {
                    ReelMoreActionButton(
                        title: self.isBookmarked ? "Remove bookmark" : "Bookmark reel",
                        subtitle: self.isBookmarked ? "Remove from your saved list" : "Save this reel to your profile",
                        symbol: self.isBookmarked ? "bookmark.slash" : "bookmark",
                        role: .normal,
                        isDisabled: self.isDeleting,
                        action: self.onToggleBookmark
                    )

                    ReelMoreActionButton(
                        title: self.isPubliclyShared ? "Remove from social" : "Share to social",
                        subtitle: self.isPubliclyShared ? "Hide it from public discovery" : "Opt this reel into public discovery",
                        symbol: self.isPubliclyShared ? "eye.slash" : "network",
                        role: .normal,
                        isDisabled: self.isDeleting,
                        action: self.onTogglePublicShare
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Share to a friend")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ReelplayTheme.black)

                        HStack(spacing: 10) {
                            TextField("@handle", text: self.$friendHandle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(ReelplayTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button {
                                self.onShareWithFriend(self.friendHandle)
                                self.friendHandle = ""
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .background(ReelplayTheme.black)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(self.isDeleting || self.friendHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ReelplayTheme.divider.opacity(0.9)))

                    ReelMoreActionButton(
                        title: "Go to original reel",
                        subtitle: "Open this reel in \(self.reel.source.capitalized)",
                        symbol: "arrow.up.right",
                        role: .normal,
                        isDisabled: self.isDeleting,
                        action: self.onOpenOriginal
                    )

                    ReelMoreActionButton(
                        title: "Delete reel",
                        subtitle: "Remove this reel and its microreels",
                        symbol: "trash",
                        role: .destructive,
                        isDisabled: self.isDeleting,
                        action: self.onDelete
                    )
                }
            }
            .padding(20)
            .padding(.bottom, max(12, UIApplication.shared.reelplayBottomSafeArea + 12))
            .background(ReelplayTheme.background)
            .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
            .shadow(color: .black.opacity(0.18), radius: 28, y: -10)
            .padding(.bottom, -UIApplication.shared.reelplayBottomSafeArea)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct ReelMoreActionButton: View {
    enum Role {
        case normal
        case destructive
    }

    let title: String
    let subtitle: String
    let symbol: String
    let role: Role
    let isDisabled: Bool
    let action: () -> Void

    private var foregroundColor: Color {
        self.role == .destructive ? .red : ReelplayTheme.black
    }

    private var iconBackground: Color {
        self.role == .destructive ? .red.opacity(0.12) : ReelplayTheme.black
    }

    private var iconForeground: Color {
        self.role == .destructive ? .red : .white
    }

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 13) {
                Image(systemName: self.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(self.iconForeground)
                    .frame(width: 42, height: 42)
                    .background(self.iconBackground)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(self.foregroundColor)

                    Text(self.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ReelplayTheme.black.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ReelplayTheme.black.opacity(0.38))
            }
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ReelplayTheme.divider.opacity(0.9)))
            .opacity(self.isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(self.isDisabled)
    }
}

private struct ReelVideoDownloadManager {
    enum DownloadError: LocalizedError {
        case missingSegment
        case photoAccessDenied
        case exportFailed

        var errorDescription: String? {
            switch self {
                case .missingSegment:
                    "There is no selected segment to download."
                case .photoAccessDenied:
                    "Allow Photos access to save reels."
                case .exportFailed:
                    "The selected segment could not be exported."
            }
        }
    }

    func saveFullVideo(from videoURL: URL) async throws {
        let localURL = try await self.localVideoURL(for: videoURL)
        defer { self.removeTemporaryFile(localURL, sourceURL: videoURL) }
        try await self.saveVideoToPhotos(localURL)
    }

    func saveSegment(from videoURL: URL, segment: ReelSegment) async throws {
        let localURL = try await self.localVideoURL(for: videoURL)
        defer { self.removeTemporaryFile(localURL, sourceURL: videoURL) }

        let exportedURL = try await self.exportSegment(from: localURL, segment: segment)
        defer { try? FileManager.default.removeItem(at: exportedURL) }
        try await self.saveVideoToPhotos(exportedURL)
    }

    private func localVideoURL(for videoURL: URL) async throws -> URL {
        guard !videoURL.isFileURL else { return videoURL }

        let (temporaryURL, response) = try await URLSession.shared.download(from: videoURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reelplay-download-\(UUID().uuidString)")
            .appendingPathExtension(videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func exportSegment(from localURL: URL, segment: ReelSegment) async throws -> URL {
        let asset = AVURLAsset(url: localURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw DownloadError.exportFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reelplay-segment-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let start = CMTime(seconds: Double(max(0, segment.startSeconds)), preferredTimescale: 600)
        let duration = CMTime(seconds: Double(max(1, segment.endSeconds - segment.startSeconds)), preferredTimescale: 600)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: start, duration: duration)
        exportSession.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                    case .completed:
                        continuation.resume()
                    case .failed, .cancelled:
                        continuation.resume(throwing: exportSession.error ?? DownloadError.exportFailed)
                    default:
                        continuation.resume(throwing: DownloadError.exportFailed)
                }
            }
        }

        return outputURL
    }

    private func saveVideoToPhotos(_ localURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw DownloadError.photoAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
        }
    }

    private func removeTemporaryFile(_ localURL: URL, sourceURL: URL) {
        guard localURL != sourceURL else { return }
        try? FileManager.default.removeItem(at: localURL)
    }
}

private struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appending(path: "gallery-import-\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

private struct ReelOCRProcessor {
    private let maxFrames = 75
    private let intervalSeconds: Double = 0.5

    func recognizeTextInSlides(_ mediaItems: [ReelMediaItem]) async throws -> [ReelOCREntry] {
        let sorted = mediaItems.sorted { $0.orderIndex < $1.orderIndex }
        var entries: [ReelOCREntry] = []

        for (index, item) in sorted.enumerated() {
            let timestamp = Double(item.orderIndex * 3)
            let imageURL = item.thumbnailURL ?? (item.type == "image" ? item.url : nil)

            if let imageURL,
               let (data, _) = try? await URLSession.shared.data(from: imageURL),
               let uiImage = UIImage(data: data),
               let cgImage = uiImage.cgImage,
               let entry = try? self.recognizeText(in: cgImage, timestamp: timestamp) {
                entries.append(entry)
            } else {
                entries.append(ReelOCREntry(
                    timestampSeconds: Int(timestamp),
                    text: "Slide \(index + 1)",
                    confidence: nil
                ))
            }
        }

        return entries
    }

    func recognizeText(in videoURL: URL, durationSeconds: Int?) async throws -> [ReelOCREntry] {
        let localURL = try await self.localVideoURL(for: videoURL)
        defer {
            if localURL != videoURL {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        return try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: localURL)
            let duration = try await asset.load(.duration)
            let assetDuration = Int(ceil(duration.seconds))
            let usableDuration = max(1, durationSeconds ?? assetDuration)
            let timestamps = self.timestamps(for: usableDuration)

            do {
                return try self.recognizeTextWithGenerator(asset: asset, timestamps: timestamps)
            } catch {
                return try await self.recognizeTextWithAssetReader(asset: asset, timestamps: timestamps)
            }
        }.value
    }

    private func localVideoURL(for videoURL: URL) async throws -> URL {
        guard videoURL.isFileURL == false else { return videoURL }

        let (temporaryURL, response) = try await URLSession.shared.download(from: videoURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-ocr-\(UUID().uuidString)")
            .appendingPathExtension(videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func timestamps(for duration: Int) -> [Double] {
        let raw = stride(from: 0.0, through: Double(duration), by: self.intervalSeconds).map { $0 }
        if raw.count <= self.maxFrames {
            return raw
        }

        return (0..<self.maxFrames).map { index in
            Double(duration) * Double(index) / Double(max(1, self.maxFrames - 1))
        }
    }

    private func recognizeTextWithGenerator(asset: AVURLAsset, timestamps: [Double]) throws -> [ReelOCREntry] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var entries: [ReelOCREntry] = []
        var previousTextKey = ""

        for timestamp in timestamps {
            try Task.checkCancellation()
            let image = try generator.copyCGImage(
                at: CMTime(seconds: timestamp, preferredTimescale: 600),
                actualTime: nil
            )
            try self.appendRecognizedEntry(
                from: image,
                timestamp: timestamp,
                entries: &entries,
                previousTextKey: &previousTextKey
            )
        }

        return entries
    }

    private func recognizeTextWithAssetReader(asset: AVURLAsset, timestamps: [Double]) async throws -> [ReelOCREntry] {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else {
            if let error = reader.error { throw error }
            return []
        }

        let sortedTargets = timestamps.sorted()
        let imageContext = CIContext()
        var targetIndex = 0
        var entries: [ReelOCREntry] = []
        var previousTextKey = ""

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard targetIndex < sortedTargets.count else { break }

            let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard seconds.isFinite else { continue }

            let targetTime = sortedTargets[targetIndex]
            guard seconds >= targetTime else { continue }

            targetIndex += 1

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { continue }
            try self.appendRecognizedEntry(
                from: cgImage,
                timestamp: targetTime,
                entries: &entries,
                previousTextKey: &previousTextKey
            )
        }

        if reader.status == .failed, let error = reader.error {
            throw error
        }

        return entries
    }

    private func appendRecognizedEntry(
        from image: CGImage,
        timestamp: Double,
        entries: inout [ReelOCREntry],
        previousTextKey: inout String
    ) throws {
        guard let entry = try self.recognizeText(in: image, timestamp: timestamp) else {
            return
        }

        let textKey = self.normalizedOCRKey(entry.text)
        guard textKey != previousTextKey else { return }

        previousTextKey = textKey
        entries.append(entry)
    }

    private func recognizeText(in image: CGImage, timestamp: Double) throws -> ReelOCREntry? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let candidates = request.results?
            .compactMap { observation -> (text: String, confidence: Float)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else { return nil }
                return (text, candidate.confidence)
            } ?? []

        let lines = self.dedupe(candidates.map(\.text))
        guard !lines.isEmpty else { return nil }

        let confidence = candidates.isEmpty
            ? nil
            : Double(candidates.map(\.confidence).reduce(0, +) / Float(candidates.count))

        return ReelOCREntry(
            timestampSeconds: Int(floor(timestamp)),
            text: lines.joined(separator: "\n"),
            confidence: confidence
        )
    }

    private func dedupe(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for line in lines {
            let normalized = line
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized.lowercased()
            guard !normalized.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(normalized)
        }

        return output
    }

    private func normalizedOCRKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class SegmentPlaybackController: ObservableObject {
    let player: AVPlayer?
    private var timeObserver: Any?
    private var progressObserver: Any?
    @Published var currentSeconds: Double = 0
    @Published var durationSeconds: Double?
    @Published var isPlaying = false
    @Published var isPreparing = false
    @Published var isReadyForDisplay = false
    @Published var canLoadSecondaryAssets = false
    private var playbackGeneration = 0

    init(videoURL: URL?, initialDurationSeconds: Int? = nil) {
        if let initialDurationSeconds, initialDurationSeconds > 0 {
            self.durationSeconds = Double(initialDurationSeconds)
        }

        if let videoURL {
            self.player = AVPlayer(url: videoURL)
            self.player?.automaticallyWaitsToMinimizeStalling = false
            self.player?.currentItem?.preferredForwardBufferDuration = 0.4
            self.configureProgressObserver()
        } else {
            self.player = nil
            self.isReadyForDisplay = true
            self.canLoadSecondaryAssets = true
        }
    }

    deinit {
        if let timeObserver {
            self.player?.removeTimeObserver(timeObserver)
        }
        if let progressObserver {
            self.player?.removeTimeObserver(progressObserver)
        }
    }

    func play(_ segment: ReelSegment) {
        guard let player else { return }
        self.removeTimeObserver()

        let start = CMTime(seconds: Double(segment.startSeconds), preferredTimescale: 600)
        self.currentSeconds = Double(segment.startSeconds)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        player.playImmediately(atRate: 1)
        self.isPlaying = true
        self.isReadyForDisplay = true
        self.unlockSecondaryAssetsAfterMainPlayback()

        self.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.seconds >= Double(segment.endSeconds) else { return }
            self?.player?.seek(
                to: CMTime(seconds: Double(segment.startSeconds), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            self?.player?.play()
        }
    }

    func playNormally() {
        guard let player else { return }
        self.removeTimeObserver()
        self.currentSeconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : self.currentSeconds
        player.playImmediately(atRate: 1)
        self.isPlaying = true
        self.isReadyForDisplay = true
        self.unlockSecondaryAssetsAfterMainPlayback()
    }

    func prepareAndPlay(_ segment: ReelSegment) async {
        guard let player else { return }
        self.playbackGeneration += 1
        let generation = self.playbackGeneration
        self.removeTimeObserver()

        let startSeconds = Double(segment.startSeconds)
        self.currentSeconds = startSeconds
        await self.preparePlayer(at: startSeconds, generation: generation)
        guard generation == self.playbackGeneration else { return }

        player.playImmediately(atRate: 1)
        self.isPlaying = true

        self.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.seconds >= Double(segment.endSeconds) else { return }
            Task { @MainActor [weak self] in
                self?.currentSeconds = Double(segment.startSeconds)
                self?.player?.seek(
                    to: CMTime(seconds: Double(segment.startSeconds), preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                self?.player?.playImmediately(atRate: 1)
            }
        }
    }

    func prepareAndPlayNormally() async {
        guard let player else { return }
        self.playbackGeneration += 1
        let generation = self.playbackGeneration
        self.removeTimeObserver()

        let currentTime = player.currentTime().seconds
        let startSeconds = currentTime.isFinite ? currentTime : self.currentSeconds
        self.currentSeconds = max(0, startSeconds)

        if startSeconds <= 0.05 {
            self.isPreparing = false
            self.isReadyForDisplay = true
            player.playImmediately(atRate: 1)
            self.isPlaying = true
            self.unlockSecondaryAssetsAfterMainPlayback()
            self.loadDurationInBackground()
            return
        }

        await self.preparePlayer(at: max(0, startSeconds), generation: generation)
        guard generation == self.playbackGeneration else { return }

        player.playImmediately(atRate: 1)
        self.isPlaying = true
        self.unlockSecondaryAssetsAfterMainPlayback()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        self.currentSeconds = seconds
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.rate == 0 {
            player.play()
            self.isPlaying = true
        } else {
            player.pause()
            self.isPlaying = false
        }
    }

    func pause() {
        self.player?.pause()
        self.isPlaying = false
        self.removeTimeObserver()
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        self.player?.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func configureProgressObserver() {
        guard let player else { return }

        self.progressObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.12, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentSeconds = time.seconds.isFinite ? time.seconds : 0
                self?.isPlaying = (self?.player?.rate ?? 0) != 0
            }
        }
    }

    private func preparePlayer(at seconds: Double, generation: Int) async {
        guard let player,
              let item = player.currentItem else {
            return
        }

        self.isPreparing = true
        self.isReadyForDisplay = false
        item.preferredForwardBufferDuration = 0.4

        self.currentSeconds = seconds
        await self.seekPlayer(to: seconds)
        guard generation == self.playbackGeneration else { return }
        self.currentSeconds = seconds
        self.isPreparing = false
        self.isReadyForDisplay = true
        self.unlockSecondaryAssetsAfterMainPlayback()

        self.loadDurationInBackground()
    }

    private func unlockSecondaryAssetsAfterMainPlayback() {
        guard !self.canLoadSecondaryAssets else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            self?.canLoadSecondaryAssets = true
        }
    }

    private func loadDurationInBackground() {
        guard let item = self.player?.currentItem else { return }
        Task { [weak self, weak item] in
            guard let self, let item else { return }
            let duration = try? await item.asset.load(.duration)
            await MainActor.run {
                if let seconds = duration?.seconds, seconds.isFinite, seconds > 0 {
                    self.durationSeconds = seconds
                }
            }
        }
    }

    private func seekPlayer(to seconds: Double) async {
        guard let player else { return }
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }
}
