import AVKit
import SwiftUI

struct ReelsListView: View {
    @EnvironmentObject var app: 📱AppModel
    @State private var reels: [ReelItem] = []
    @State private var importText = ""
    @State private var selectedReel: ReelItem?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var importStageIndex = 0
    @State private var importingURL: URL?
    @State private var errorMessage: String?

    private let importStages = [
        "Reading reel",
        "Transcribing audio",
        "Finding key moments",
        "Building microreels",
    ]

    var body: some View {
        NavigationStack {
            List {
                self.importSection
                self.reelsSection
            }
            .navigationTitle("Reels")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await self.loadReels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(self.isLoading || self.isImporting)
                }
            }
            .overlay {
                if self.isLoading && self.reels.isEmpty {
                    ProgressView()
                }
            }
            .overlay {
                if self.isImporting {
                    ImportReelOverlay(
                        sourceURL: self.importingURL,
                        stages: self.importStages,
                        activeStageIndex: self.importStageIndex
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
                Task { await self.importCurrentURL() }
            }
            .navigationDestination(item: self.$selectedReel) { reel in
                ReelDetailView(reel: reel)
            }
        }
        .tag(🔖Tab.reels)
        .tabItem { Label("Reels", systemImage: "play.rectangle") }
    }
}

private extension ReelsListView {
    var importSection: some View {
        Section {
            TextField("Instagram or TikTok URL", text: self.$importText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button {
                    Task { await self.importCurrentURL() }
                } label: {
                    Label(self.isImporting ? "Importing" : "Import", systemImage: "square.and.arrow.down")
                }
                .disabled(self.isImporting || self.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                #if os(iOS)
                Button {
                    if let text = UIPasteboard.general.string {
                        self.importText = text
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                #endif
            }

            if self.isImporting {
                Label(self.importStages[min(self.importStageIndex, self.importStages.count - 1)], systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    var reelsSection: some View {
        Section {
            if self.reels.isEmpty && !self.isLoading {
                ContentUnavailableView("No reels saved", systemImage: "play.slash", description: Text("Paste an Instagram Reel URL to create timestamped notes."))
            } else {
                ForEach(self.reels) { reel in
                    Button {
                        self.selectedReel = reel
                    } label: {
                        ReelRow(reel: reel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func loadReels() async {
        do {
            self.errorMessage = nil
            self.isLoading = true
            self.reels = try await ReelService().listReels()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
    }

    func importCurrentURL() async {
        let text = self.importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text) else {
            self.errorMessage = "Enter a valid reel URL."
            💥Feedback.error()
            return
        }

        do {
            self.errorMessage = nil
            self.isImporting = true
            self.importingURL = url
            self.importStageIndex = 0
            let reel = try await ReelService().importReel(url: url)
            self.reels.removeAll { $0.id == reel.id }
            self.reels.insert(reel, at: 0)
            self.selectedReel = reel
            self.importText = ""
            self.app.sharedReelURL = nil
            💥Feedback.success()
        } catch {
            self.errorMessage = error.localizedDescription
            💥Feedback.error()
        }
        self.isImporting = false
        self.importingURL = nil
    }

    func animateImportStages() async {
        while !Task.isCancelled && self.isImporting {
            try? await Task.sleep(for: .seconds(2.2))
            guard self.isImporting else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.importStageIndex = min(self.importStageIndex + 1, self.importStages.count - 1)
            }
        }
    }
}

private struct ImportReelOverlay: View {
    let sourceURL: URL?
    let stages: [String]
    let activeStageIndex: Int
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .secondarySystemBackground),
                                    Color.black.opacity(0.92),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            VStack(spacing: 14) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .scaleEffect(self.pulse ? 1.08 : 0.96)

                                VStack(spacing: 7) {
                                    ForEach(0..<5) { index in
                                        Capsule()
                                            .fill(.white.opacity(index == self.activeStageIndex % 5 ? 0.74 : 0.24))
                                            .frame(width: CGFloat(72 + (index * 18)), height: 8)
                                    }
                                }
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(self.activeStage)
                            .font(.headline)
                            .foregroundStyle(.white)

                        if let sourceURL {
                            Text(sourceURL.host(percentEncoded: false) ?? sourceURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 210, height: 330)
                .shadow(radius: 18)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(self.stages.enumerated()), id: \.offset) { index, stage in
                        HStack(spacing: 10) {
                            Image(systemName: index < self.activeStageIndex ? "checkmark.circle.fill" : index == self.activeStageIndex ? "circle.dotted" : "circle")
                                .foregroundStyle(index <= self.activeStageIndex ? .green : .secondary)
                                .frame(width: 22)

                            Text(stage)
                                .font(.subheadline)
                                .foregroundStyle(index <= self.activeStageIndex ? .primary : .secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(16)
                .frame(maxWidth: 320, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
    }

    private var activeStage: String {
        self.stages[min(self.activeStageIndex, self.stages.count - 1)]
    }
}

private struct ReelRow: View {
    let reel: ReelItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: reel.thumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.secondary.opacity(0.18)
                    Image(systemName: "play.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 82, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(reel.title ?? reel.caption ?? "Saved reel")
                    .font(.headline)
                    .lineLimit(2)

                if let summary = reel.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(reel.creatorUsername.map { "@\($0)" } ?? reel.source.capitalized)
                    Text("\(reel.segments.count) segments")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReelDetailView: View {
    let reel: ReelItem

    var body: some View {
        SegmentReelPlayerView(reel: reel)
        .navigationTitle(reel.title ?? "Reel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SegmentReelPlayerView: View {
    let reel: ReelItem
    @StateObject private var playback: SegmentPlaybackController
    @State private var activeSegmentID: UUID?

    init(reel: ReelItem) {
        self.reel = reel
        self._playback = StateObject(wrappedValue: SegmentPlaybackController(videoURL: reel.videoURL))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(self.reel.segments) { segment in
                        SegmentPageView(
                            reel: self.reel,
                            segment: segment,
                            player: self.playback.player,
                            isActive: self.activeSegmentID == segment.id
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
            .onAppear {
                self.activeSegmentID = self.reel.segments.first?.id
                if let segment = self.reel.segments.first {
                    self.playback.play(segment)
                }
            }
            .onChange(of: self.activeSegmentID) { _, id in
                guard let id,
                      let segment = self.reel.segments.first(where: { $0.id == id }) else {
                    return
                }

                self.playback.play(segment)
                💥Feedback.selection()
            }
            .onDisappear {
                self.playback.pause()
            }
        }
    }
}

private struct SegmentPageView: View {
    let reel: ReelItem
    let segment: ReelSegment
    let player: AVPlayer?
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if self.isActive, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                AsyncImage(url: self.reel.thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                HStack {
                    Text("\(Self.format(self.segment.startSeconds))-\(Self.format(self.segment.endSeconds))")
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.86))

                    Spacer()

                    Image(systemName: self.isActive ? "play.fill" : "pause.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.86))
                }

                Text(self.segment.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !self.segment.description.isEmpty {
                    Text(self.segment.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(4)
                }

                if let creator = self.reel.creatorUsername {
                    Text("@\(creator)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
        }
    }

    static func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

@MainActor
private final class SegmentPlaybackController: ObservableObject {
    let player: AVPlayer?
    private var timeObserver: Any?

    init(videoURL: URL?) {
        if let videoURL {
            self.player = AVPlayer(url: videoURL)
        } else {
            self.player = nil
        }
    }

    deinit {
        if let timeObserver {
            self.player?.removeTimeObserver(timeObserver)
        }
    }

    func play(_ segment: ReelSegment) {
        guard let player else { return }
        self.removeTimeObserver()

        let start = CMTime(seconds: Double(segment.startSeconds), preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()

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

    func pause() {
        self.player?.pause()
        self.removeTimeObserver()
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        self.player?.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }
}
