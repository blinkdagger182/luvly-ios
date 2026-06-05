import AVKit
import CoreImage
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
    @State private var reels: [ReelItem] = []
    @State private var selectedTab: ReelplayTab = .home
    @State private var selectedReel: ReelItem?
    @State private var searchText = ""
    @State private var importText = ""
    @State private var selectedHomeCollectionID: String?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var isProcessingPendingOCR = false
    @State private var importStageIndex = 0
    @State private var importingURL: URL?
    @State private var isPreparingSelectedReel = false
    @State private var selectedReelStageIndex = 0
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
                        activeStageIndex: self.importStageIndex
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
                        activeStageIndex: self.selectedReelStageIndex
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: self.$selectedReel) { reel in
                ReelDetailView(reel: reel)
            }
        }
        .task {
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
    }

    @ViewBuilder
    private var content: some View {
        switch self.selectedTab {
            case .home:
                ReelplayHomeScreen(
                    reels: self.reels,
                    collections: self.collections,
                    isLoading: self.isLoading,
                    errorMessage: self.errorMessage,
                    selectedCollectionID: self.$selectedHomeCollectionID,
                    onSelectReel: { self.prepareAndOpenReel($0) },
                    onSelectCollection: { collection in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            self.selectedHomeCollectionID = self.selectedHomeCollectionID == collection.id ? nil : collection.id
                        }
                    },
                    onRefresh: { Task { await self.loadReels() } },
                    onImport: { self.selectedTab = .add },
                    searchText: self.$searchText
                )
            case .search:
                ReelplaySearchScreen(
                    reels: self.reels,
                    searchText: self.$searchText,
                    onSelectReel: { self.prepareAndOpenReel($0) }
                )
            case .add:
                ReelplayImportScreen(
                    importText: self.$importText,
                    isImporting: self.isImporting,
                    errorMessage: self.errorMessage,
                    onImport: { Task { await self.importCurrentURL() } }
                )
            case .collections:
                ReelplayCollectionsScreen(
                    collections: self.collections,
                    reels: self.reels,
                    onSelectReel: { self.prepareAndOpenReel($0) }
                )
            case .profile:
                ReelplayProfileScreen(reels: self.reels, collections: self.collections)
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

    private func loadReels() async {
        do {
            self.errorMessage = nil
            self.isLoading = true
            self.reels = try await ReelService().listReels()
            Task { await self.processPendingOCRReelsIfNeeded() }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
    }

    private func importCurrentURL() async {
        let text = self.importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), 📱AppModel.isSupportedReelURL(url) else {
            self.errorMessage = "Paste a valid Instagram or TikTok reel link."
            💥Feedback.error()
            return
        }

        await self.importURL(url)
    }

    private func importURL(_ url: URL) async {
        do {
            self.errorMessage = nil
            self.isImporting = true
            self.importingURL = url
            self.importStageIndex = 0

            var reel = try await ReelService().importReel(url: url)
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
        self.importingURL = nil
    }

    private func animateImportStages() async {
        while !Task.isCancelled && self.isImporting {
            try? await Task.sleep(for: .seconds(2.1))
            guard self.isImporting else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                self.importStageIndex = min(self.importStageIndex + 1, self.importStages.count - 1)
            }
        }
    }

    private func prepareAndOpenReel(_ reel: ReelItem) {
        guard !self.isPreparingSelectedReel else { return }

        if !reel.needsOCRProcessing, reel.isMicroreelReady {
            self.selectedReel = reel
            return
        }

        self.preparingReelTitle = reel.title
        self.selectedReelStageIndex = 0
        self.isPreparingSelectedReel = true

        Task {
            let animationTask = Task { await self.animateSelectedReelStages() }
            let preparedReel = await self.processOCRWithTimeout(for: reel)
            animationTask.cancel()
            await MainActor.run {
                self.selectedReel = preparedReel
                self.isPreparingSelectedReel = false
                self.preparingReelTitle = nil
            }
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
            try? await Task.sleep(for: .seconds(1.6))
            guard self.isPreparingSelectedReel else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                self.selectedReelStageIndex = min(self.selectedReelStageIndex + 1, self.selectedReelStages.count - 1)
            }
        }
    }

    private func processOCR(for reel: ReelItem) async -> ReelItem {
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
    let reels: [ReelItem]
    let collections: [ReelCollection]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedCollectionID: String?
    let onSelectReel: (ReelItem) -> Void
    let onSelectCollection: (ReelCollection) -> Void
    let onRefresh: () -> Void
    let onImport: () -> Void
    @Binding var searchText: String

    private var selectedCollection: ReelCollection? {
        self.collections.first { $0.id == self.selectedCollectionID }
    }

    private var selectedCollectionReels: [ReelItem] {
        guard let selectedCollection else { return [] }
        return self.reels.filter { ReelCollection.categoryName(for: $0) == selectedCollection.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    Text("Reelplay")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(ReelplayTheme.black)

                    Spacer()

                    Button(action: self.onRefresh) {
                        Image(systemName: "bell")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ReelplayTheme.black)
                            .frame(width: 38, height: 38)
                            .background(ReelplayTheme.surface)
                            .clipShape(Circle())
                    }
                    .disabled(self.isLoading)
                }

                ReelplaySearchField(text: self.$searchText, placeholder: "Search your reels...")

                SectionHeader(title: "Collections", actionTitle: "See all")

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(self.collections.prefix(5)) { collection in
                            Button {
                                self.onSelectCollection(collection)
                            } label: {
                                CollectionMiniCard(
                                    collection: collection,
                                    isSelected: self.selectedCollectionID == collection.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)

                if let selectedCollection {
                    SectionHeader(title: selectedCollection.name, actionTitle: "Clear")
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                self.selectedCollectionID = nil
                            }
                        }

                    VStack(spacing: 10) {
                        ForEach(self.selectedCollectionReels) { reel in
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                ReelListRow(reel: reel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionHeader(title: "Recently Added")

                VStack(spacing: 10) {
                    if self.isLoading && self.reels.isEmpty {
                        PremiumHomeLoadingCard()
                    } else if self.reels.isEmpty {
                        EmptyHomeCard(onImport: self.onImport)
                    } else {
                        ForEach(self.reels.prefix(8)) { reel in
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                ReelListRow(reel: reel)
                            }
                            .buttonStyle(.plain)
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
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReelplayImportScreen: View {
    @Binding var importText: String
    let isImporting: Bool
    let errorMessage: String?
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Import Reel")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .leading) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a TikTok or\nInstagram link")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(ReelplayTheme.black)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("We will handle the rest.")
                        .font(.subheadline)
                        .foregroundStyle(ReelplayTheme.mutedText)
                }

                HStack(spacing: 10) {
                    TextField("https://www.instagram.com/...", text: self.$importText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)

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
                .padding(16)
                .background(ReelplayTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("How it works")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    ImportStepRow(symbol: "square.and.arrow.down", title: "We fetch the reel", bodyText: "Extract captions, audio and metadata")
                    ImportStepRow(symbol: "wand.and.stars", title: "Create smart steps", bodyText: "AI breaks it down into timestamped steps")
                    ImportStepRow(symbol: "folder.badge.plus", title: "Save and organize", bodyText: "Add to collections and replay any moment")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReelplayCollectionsScreen: View {
    let collections: [ReelCollection]
    let reels: [ReelItem]
    let onSelectReel: (ReelItem) -> Void
    @State private var selectedCollectionID: String?

    private var selectedCollection: ReelCollection? {
        self.collections.first { $0.id == self.selectedCollectionID }
    }

    private var selectedCollectionReels: [ReelItem] {
        guard let selectedCollection else { return [] }
        return self.reels.filter { ReelCollection.categoryName(for: $0) == selectedCollection.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Text("Collections")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(ReelplayTheme.black)

                VStack(spacing: 12) {
                    ForEach(self.collections) { collection in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                self.selectedCollectionID = self.selectedCollectionID == collection.id ? nil : collection.id
                            }
                        } label: {
                            CollectionListCard(
                                collection: collection,
                                isSelected: self.selectedCollectionID == collection.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedCollection {
                    SectionHeader(title: selectedCollection.name, actionTitle: "Selected")

                    VStack(spacing: 10) {
                        ForEach(self.selectedCollectionReels) { reel in
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                ReelListRow(reel: reel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !self.reels.isEmpty {
                    SectionHeader(title: "Recently Added")

                    VStack(spacing: 10) {
                        ForEach(self.reels.prefix(12)) { reel in
                            Button {
                                self.onSelectReel(reel)
                            } label: {
                                ReelListRow(reel: reel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReelplaySearchScreen: View {
    let reels: [ReelItem]
    @Binding var searchText: String
    let onSelectReel: (ReelItem) -> Void

    private var filteredReels: [ReelItem] {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return self.reels.filter { reel in
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Search")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ReelplayTheme.black)

                ReelplaySearchField(text: self.$searchText, placeholder: "Search reels, steps, creators...")

                if self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchSuggestions()
                } else {
                    VStack(spacing: 10) {
                        if self.filteredReels.isEmpty {
                            Text("No reels found")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ReelplayTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                        } else {
                            ForEach(self.filteredReels) { reel in
                                Button {
                                    self.onSelectReel(reel)
                                } label: {
                                    ReelListRow(reel: reel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReelplayProfileScreen: View {
    let reels: [ReelItem]
    let collections: [ReelCollection]

    private var savedHours: Int {
        max(1, self.reels.compactMap(\.durationSeconds).reduce(0, +) / 3600)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Text("Profile")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(ReelplayTheme.black)

                VStack(spacing: 12) {
                    Circle()
                        .fill(ReelplayTheme.accent)
                        .frame(width: 78, height: 78)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(ReelplayTheme.black)
                        }

                    VStack(spacing: 3) {
                        Text("Reelplay User")
                            .font(.headline.weight(.bold))
                        Text("saved@reelplay.app")
                            .font(.caption)
                            .foregroundStyle(ReelplayTheme.mutedText)
                    }
                }

                HStack(spacing: 0) {
                    ProfileStat(value: "\(self.reels.count)", label: "Reels Saved")
                    ProfileStat(value: "\(self.collections.filter { $0.count > 0 }.count)", label: "Collections")
                    ProfileStat(value: "\(self.savedHours)h", label: "Time Saved")
                }

                VStack(spacing: 0) {
                    ProfileMenuRow(symbol: "square.and.arrow.down", title: "Downloads", trailing: "Coming Soon")
                    ProfileMenuRow(symbol: "bookmark", title: "Saved Steps")
                    ProfileMenuRow(symbol: "clock", title: "Watch History")
                    ProfileMenuRow(symbol: "bell", title: "Notifications")
                    ProfileMenuRow(symbol: "gearshape", title: "Settings")
                    ProfileMenuRow(symbol: "questionmark.circle", title: "Help & Feedback")
                }
                .background(ReelplayTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReelplayTheme.divider))
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
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
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: tab == .add ? 22 : 20, weight: tab == .add ? .bold : .regular))
                            .frame(width: tab == .add ? 52 : 44, height: tab == .add ? 52 : 32)
                            .foregroundStyle(tab == .add ? .white : self.selectedTab == tab ? ReelplayTheme.black : ReelplayTheme.black.opacity(0.62))
                            .background {
                                if tab == .add {
                                    Circle()
                                        .fill(ReelplayTheme.black)
                                        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                                }
                            }

                        if tab != .add {
                            Text(tab.title)
                                .font(.caption2.weight(self.selectedTab == tab ? .bold : .regular))
                                .foregroundStyle(self.selectedTab == tab ? ReelplayTheme.black : ReelplayTheme.black.opacity(0.58))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text("")
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(ReelplayTheme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ReelplayTheme.divider)
                .frame(height: 1)
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

    private static func displayName(_ value: String) -> String {
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
                AsyncImage(url: self.reel.thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
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

private struct EmptyHomeCard: View {
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ReelplayPreviewPanel(
                title: "Replay any reel",
                subtitle: "Saved moments become timestamped steps."
            )
            .frame(height: 214)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save your first reel")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ReelplayTheme.black)
                Text("Paste or share an Instagram or TikTok link and Reelplay will build replayable microreels from the moments that matter.")
                    .font(.subheadline)
                    .foregroundStyle(ReelplayTheme.mutedText)
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
        }
        .padding(16)
        .background(ReelplayTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 22, y: 10)
    }
}

private struct PremiumHomeLoadingCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ReelplayPreviewPanel(
                title: "Preparing your library",
                subtitle: "Syncing saved reels and pending microreels.",
                isLoading: true
            )
            .frame(height: 214)

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
        .padding(16)
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
    let content: (String) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(self.items, id: \.self) { item in
                self.content(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
    @State private var spin = false
    @State private var pulse = false

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
                        .trim(from: 0.02, to: 0.78)
                        .stroke(ReelplayTheme.black, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 176, height: 176)
                        .rotationEffect(.degrees(self.spin ? 360 : 0))

                    ReelplayAppIconView()
                        .frame(width: 92, height: 92)
                        .scaleEffect(self.pulse ? 1.06 : 0.96)
                }

                VStack(spacing: 8) {
                    Text(self.headline)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ReelplayTheme.black)

                    Text(self.subheadline)
                        .font(.footnote)
                        .foregroundStyle(ReelplayTheme.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

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
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                self.spin = true
            }
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

    var body: some View {
        ReelSummaryView(reel: self.reel)
            .toolbar(.hidden, for: .navigationBar)
            .background(InteractivePopGestureEnabler())
    }
}

private struct ReelSummaryView: View {
    let reel: ReelItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: SegmentPlaybackController
    @State private var selectedTab = 0
    @State private var expandedSegmentID: UUID?
    @State private var focusedSegmentID: UUID?
    @State private var isShowingFullscreenVideo = false
    @State private var expandDragTranslation: CGFloat = 0

    init(reel: ReelItem) {
        self.reel = reel
        self._playback = StateObject(wrappedValue: SegmentPlaybackController(videoURL: reel.videoURL))
    }

    private var segments: [ReelSegment] {
        self.reel.playbackSegments
    }

    private var expandedSegment: ReelSegment? {
        guard let expandedSegmentID else { return nil }
        return self.segments.first { $0.id == expandedSegmentID }
    }

    private var heroHeight: CGFloat { 372 }

    var body: some View {
        ZStack {
            Color(hex: 0x0F0F10)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                        Image(systemName: "bookmark")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 38, height: 38)
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
                .padding(.top, self.heroHeight)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                ReelSummaryHero(
                    reel: self.reel,
                    player: self.playback.player,
                    currentSeconds: self.playback.currentSeconds,
                    durationSeconds: self.playback.durationSeconds ?? Double(self.reel.durationSeconds ?? 0),
                    isPlaying: self.playback.isPlaying,
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
                        Image(systemName: "square.and.arrow.down")
                        Image(systemName: "ellipsis")
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
                        }
                    },
                    onCollapseToPinned: {
                        self.isShowingFullscreenVideo = false
                    }
                )
                .zIndex(30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(hex: 0x0F0F10))
        .onAppear {
            self.playback.playNormally()
        }
        .onChange(of: self.focusedSegmentID) { _, _ in
            if let focusedSegmentID,
               let focusedSegment = self.segments.first(where: { $0.id == focusedSegmentID }) {
                self.playback.play(focusedSegment)
            } else {
                self.playback.playNormally()
            }
        }
        .onDisappear {
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

    private func expandVideoSwipe() -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let mostlyVertical = abs(value.translation.height) > abs(value.translation.width) * 1.2
                guard mostlyVertical else { return }
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
    let onSeek: (Double) -> Void
    let onTogglePlayPause: () -> Void
    let onOpenFullscreen: () -> Void
    @State private var scrubSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var areControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Button(action: self.showControlsTemporarily) {
                ZStack {
                    Color.black

                    if let player {
                        FullScreenReelVideoPlayer(player: player, videoGravity: .resizeAspect)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        AsyncImage(url: self.reel.thumbnailURL) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ReelThumbnailPlaceholder()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            LinearGradient(
                colors: [.black.opacity(0.12), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()

                VStack(spacing: 8) {
                    HStack {
                        Button(action: self.onOpenFullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.42))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()
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
        }
        .frame(height: 372)
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
                    SegmentThumbnail(reel: self.reel, segment: self.segment)
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SegmentFrameThumbnail(
                videoURL: self.reel.videoURL,
                fallbackURL: self.reel.thumbnailURL,
                seconds: self.segment.startSeconds
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
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if self.didFail {
                AsyncImage(url: self.fallbackURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
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
        "\(self.videoURL?.absoluteString ?? "missing")-\(self.seconds)"
    }

    @MainActor
    private func loadFrame() async {
        self.image = nil
        self.didFail = false

        guard let videoURL else {
            self.didFail = true
            return
        }

        do {
            let thumbnail = try await Self.extractFrame(from: videoURL, at: self.seconds)
            self.image = thumbnail
        } catch {
            self.didFail = true
        }
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

private struct SegmentThumbnailLoadingPlaceholder: View {
    let fallbackURL: URL?

    var body: some View {
        ZStack {
            AsyncImage(url: self.fallbackURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
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
                            AsyncImage(url: self.reel.thumbnailURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
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

            if let player {
                Button(action: self.showControlsTemporarily) {
                    FullScreenReelVideoPlayer(player: player)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
            } else {
                Button(action: self.showControlsTemporarily) {
                    Color.black
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
            self.showControlsTemporarily()
        }
        .onChange(of: self.currentSeconds) { _, seconds in
            guard !self.isScrubbing else { return }
            self.scrubSeconds = min(max(0, seconds), self.safeDuration)
        }
        .onDisappear {
            self.hideControlsTask?.cancel()
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
                self.activeSegmentID = initialSegment?.id
                if let segment = initialSegment {
                    self.playback.play(segment)
                }
            }
            .onChange(of: self.activeSegmentID) { _, id in
                guard let id,
                      let segment = self.segments.first(where: { $0.id == id }) else {
                    return
                }

                self.playback.play(segment)
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
    var isMicroreelReady: Bool {
        return self.segments.count >= 2
    }

    var needsOCRProcessing: Bool {
        guard self.videoURL != nil else { return false }

        let retryableStatuses = ["needs_ocr", "ready_basic", "ocr_failed"]
        if retryableStatuses.contains(self.status) {
            return true
        }

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

private extension UIApplication {
    var reelplayTopSafeArea: CGFloat {
        self.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }
}

private struct SegmentPageView: View {
    let reel: ReelItem
    let segment: ReelSegment
    let player: AVPlayer?
    let isActive: Bool
    let showDetails: Bool

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if self.isActive, let player {
                FullScreenReelVideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                AsyncImage(url: self.reel.thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ReelThumbnailPlaceholder()
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

private struct FullScreenReelVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

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

private struct ReelOCRProcessor {
    private let maxFrames = 75
    private let intervalSeconds = 1

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

    private func timestamps(for duration: Int) -> [Int] {
        let raw = stride(from: 0, through: duration, by: self.intervalSeconds).map { $0 }
        if raw.count <= self.maxFrames {
            return raw
        }

        return (0..<self.maxFrames).map { index in
            Int(round(Double(duration) * Double(index) / Double(max(1, self.maxFrames - 1))))
        }
    }

    private func recognizeTextWithGenerator(asset: AVURLAsset, timestamps: [Int]) throws -> [ReelOCREntry] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

        var entries: [ReelOCREntry] = []
        var previousTextKey = ""

        for timestamp in timestamps {
            try Task.checkCancellation()
            let image = try generator.copyCGImage(
                at: CMTime(seconds: Double(timestamp), preferredTimescale: 600),
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

    private func recognizeTextWithAssetReader(asset: AVURLAsset, timestamps: [Int]) async throws -> [ReelOCREntry] {
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

        let targetTimestamps = Set(timestamps)
        let imageContext = CIContext()
        var processedTimestamps = Set<Int>()
        var entries: [ReelOCREntry] = []
        var previousTextKey = ""

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard seconds.isFinite else { continue }

            let timestamp = Int(floor(seconds))
            guard targetTimestamps.contains(timestamp), !processedTimestamps.contains(timestamp) else {
                continue
            }

            processedTimestamps.insert(timestamp)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { continue }
            try self.appendRecognizedEntry(
                from: cgImage,
                timestamp: timestamp,
                entries: &entries,
                previousTextKey: &previousTextKey
            )

            if processedTimestamps.count >= targetTimestamps.count {
                break
            }
        }

        if reader.status == .failed, let error = reader.error {
            throw error
        }

        return entries
    }

    private func appendRecognizedEntry(
        from image: CGImage,
        timestamp: Int,
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

    private func recognizeText(in image: CGImage, timestamp: Int) throws -> ReelOCREntry? {
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
            timestampSeconds: timestamp,
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

    init(videoURL: URL?) {
        if let videoURL {
            self.player = AVPlayer(url: videoURL)
            self.configureProgressObserver()
        } else {
            self.player = nil
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
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        self.isPlaying = true

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
        player.play()
        self.isPlaying = true
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentSeconds = seconds
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

        Task { [weak self, weak player] in
            guard let self,
                  let asset = player?.currentItem?.asset else {
                return
            }
            let duration = try? await asset.load(.duration)
            await MainActor.run {
                if let seconds = duration?.seconds, seconds.isFinite, seconds > 0 {
                    self.durationSeconds = seconds
                }
            }
        }

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
}
