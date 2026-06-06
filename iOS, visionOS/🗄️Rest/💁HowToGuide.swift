import SwiftUI

struct 💁HowToGuideSection: View {
    var body: some View {
        Section {
#if os(iOS)
            NavigationLink {
                💁HowToHomeScreen()
            } label: {
                Label("How to add home screen widget", systemImage: "questionmark")
            }
            NavigationLink {
                💁HowToLockScreen()
            } label: {
                Label("How to add lock screen widget", systemImage: "questionmark")
            }
#endif
            💁ICloudSyncSection()
        } header: {
            Text("Guide")
        }
    }
}

struct 💁HowToOnBoarding: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPage = 0

    private let pages = ReelplayOnboardingPage.all

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ReelplayOnboardingCarousel()
                    .frame(height: min(max(proxy.size.height * 0.24, 184), 238))
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 6)

                TabView(selection: self.$selectedPage) {
                    ForEach(Array(self.pages.enumerated()), id: \.offset) { index, page in
                        ReelplayOnboardingPageView(page: page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity)

                ReelplayOnboardingDots(count: self.pages.count, selectedPage: self.selectedPage)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        if self.selectedPage < self.pages.count - 1 {
                            self.selectedPage += 1
                        } else {
                            self.dismiss()
                        }
                    }
                } label: {
                    Text(self.selectedPage == self.pages.count - 1 ? "Get Started" : "Continue")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(ReelplayOnboardingTheme.black)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReelplayOnboardingTheme.background.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                Button {
                    self.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ReelplayOnboardingTheme.black.opacity(0.62))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.72))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.black.opacity(0.06)))
                }
                .padding(.trailing, 18)
                .padding(.top, proxy.safeAreaInsets.top + 8)
            }
        }
    }
}

private enum ReelplayOnboardingTheme {
    static let black = Color(hex: 0x111111)
    static let background = Color(hex: 0xFBF5EF)
    static let card = Color.white.opacity(0.72)
    static let accent = Color(hex: 0xB98545)
    static let muted = Color.black.opacity(0.54)
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

private struct ReelplayOnboardingPage: Hashable {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content
    let activeStep: Int

    enum Content: Hashable {
        case importForm
        case processing
        case steps
    }

    static let all: [Self] = [
        .init(
            icon: "link",
            title: "Import any reel",
            subtitle: "Paste a link or share from Instagram or TikTok to save it in seconds.",
            content: .importForm,
            activeStep: 0
        ),
        .init(
            icon: "list.bullet.rectangle",
            title: "We process the video for you",
            subtitle: "We detect key moments and turn every reel into simple step-by-step guidance.",
            content: .processing,
            activeStep: 1
        ),
        .init(
            icon: "list.number",
            title: "See every step clearly",
            subtitle: "Get a clean step-by-step breakdown with timestamps so you can replay and follow along easily.",
            content: .steps,
            activeStep: 2
        ),
    ]
}

private struct ReelplayOnboardingCarousel: View {
    private let reels = OnboardingReelCard.sample

    var body: some View {
        GeometryReader { proxy in
            let centerWidth = min(proxy.size.width * 0.27, 128)
            let sideWidth = centerWidth * 0.74
            let spacing = max(6, proxy.size.width * 0.018)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(self.reels.enumerated()), id: \.element.id) { index, reel in
                    OnboardingReelCardView(reel: reel, isFeatured: index == 2)
                        .frame(width: index == 2 ? centerWidth : sideWidth, height: index == 2 ? centerWidth * 1.5 : centerWidth * 1.28)
                        .rotationEffect(.degrees(Self.rotation(for: index)))
                        .offset(y: index == 2 ? -8 : 10)
                        .zIndex(index == 2 ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
        }
    }

    private static func rotation(for index: Int) -> Double {
        [-8, -3, 0, 4, 7][index]
    }
}

private struct OnboardingReelCard: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let time: String
    let creator: String
    let symbol: String
    let colors: [Color]

    static let sample: [Self] = {
        let pasta = Self(title: "Creamy Garlic Pasta", subtitle: "Quick & Easy Recipe", time: "15:14", creator: "kitchen.jane", symbol: "fork.knife", colors: [Color(hex: 0x7A5A36), Color(hex: 0xD9A54D)])
        let dance = Self(title: "Dance Tutorial", subtitle: "Hip Hop Basics", time: "3:10", creator: "dance.soul", symbol: "figure.socialdance", colors: [Color(hex: 0x5D4634), Color(hex: 0xC98A48)])
        let workout = Self(title: "Glute Boost Workout", subtitle: "Stronger • Lifted • Confident", time: "23:10", creator: "fit.with.liv", symbol: "figure.strengthtraining.traditional", colors: [Color(hex: 0x2B2A26), Color(hex: 0x8C7253)])
        let stretch = Self(title: "15 min Stretch", subtitle: "Morning Flow", time: "11:05", creator: "mindful.movement", symbol: "figure.flexibility", colors: [Color(hex: 0xB99572), Color(hex: 0xE0C5A3)])
        let routine = Self(title: "5 AM Routine", subtitle: "Productive Start", time: "9:25", creator: "the.daily.plan", symbol: "sun.max", colors: [Color(hex: 0x6D604A), Color(hex: 0xD9C49B)])
        return [pasta, dance, workout, stretch, routine]
    }()
}

private struct OnboardingReelCardView: View {
    let reel: OnboardingReelCard
    let isFeatured: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: self.reel.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: self.reel.symbol)
                .font(.system(size: self.isFeatured ? 42 : 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(self.reel.time)
                    Spacer()
                    Image(systemName: "heart")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))

                Text(self.reel.title)
                    .font(.system(size: self.isFeatured ? 16 : 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(self.reel.subtitle)
                    .font(.system(size: self.isFeatured ? 9 : 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(.white.opacity(0.88))
                        .frame(width: self.isFeatured ? 17 : 11, height: self.isFeatured ? 17 : 11)
                    Text(self.reel.creator)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "ellipsis")
                }
                .font(.system(size: self.isFeatured ? 8 : 6, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.top, 3)
            }
            .padding(self.isFeatured ? 12 : 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: self.isFeatured ? 14 : 10))
        .overlay(RoundedRectangle(cornerRadius: self.isFeatured ? 14 : 10).stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: self.isFeatured ? 18 : 10, y: self.isFeatured ? 10 : 6)
    }
}

private struct ReelplayOnboardingPageView: View {
    let page: ReelplayOnboardingPage

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                Text(self.page.title)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(ReelplayOnboardingTheme.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(self.page.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ReelplayOnboardingTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch self.page.content {
                case .importForm:
                    OnboardingImportPanel()
                case .processing:
                    OnboardingProcessingPanel()
                case .steps:
                    OnboardingStepsPanel()
            }

            OnboardingStepList(activeStep: self.page.activeStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct OnboardingImportPanel: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(ReelplayOnboardingTheme.muted)
                Text("https://www.instagram.com/reel/DAxyz123abc/")
                    .font(.subheadline)
                    .foregroundStyle(ReelplayOnboardingTheme.muted)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ReelplayOnboardingTheme.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(.white.opacity(0.62))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ReelplayOnboardingTheme.divider))

            HStack(spacing: 12) {
                OnboardingSmallAction(title: "Paste link", symbol: "doc.on.clipboard")
                OnboardingSmallAction(title: "Share reel", symbol: "square.and.arrow.up")
            }
        }
        .padding(12)
        .background(ReelplayOnboardingTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.5)))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct OnboardingSmallAction: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbol)
                .foregroundStyle(ReelplayOnboardingTheme.accent)
            Text(self.title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayOnboardingTheme.divider))
    }
}

private struct OnboardingProcessingPanel: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color(hex: 0xF0E2D1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(ReelplayOnboardingTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("72%")
                    .font(.headline.weight(.semibold))
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                OnboardingProcessRow(title: "Reading reel", state: .done)
                OnboardingProcessRow(title: "Transcribing audio", state: .done)
                OnboardingProcessRow(title: "Finding key moments", state: .active)
                OnboardingProcessRow(title: "Building steps", state: .pending)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(ReelplayOnboardingTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.5)))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private enum OnboardingProcessState {
    case done, active, pending
}

private struct OnboardingProcessRow: View {
    let title: String
    let state: OnboardingProcessState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(self.state == .pending ? ReelplayOnboardingTheme.muted.opacity(0.35) : .white)
                .frame(width: 19, height: 19)
                .background(self.state == .pending ? .clear : ReelplayOnboardingTheme.accent)
                .clipShape(Circle())
                .overlay(Circle().stroke(self.state == .pending ? ReelplayOnboardingTheme.muted.opacity(0.32) : .clear, lineWidth: 2))

            Text(self.title)
                .font(.caption.weight(self.state == .active ? .bold : .medium))
                .foregroundStyle(self.state == .pending ? ReelplayOnboardingTheme.muted.opacity(0.62) : ReelplayOnboardingTheme.black)
        }
    }

    private var symbol: String {
        switch self.state {
            case .done: "checkmark"
            case .active: "sparkles"
            case .pending: "circle"
        }
    }
}

private struct OnboardingStepsPanel: View {
    private let steps = [
        ("Hip Thrust", "Drive through your heels and lift your hips up.", "00:00"),
        ("Glute Bridge Hold", "Squeeze your glutes and hold at the top.", "00:42"),
        ("Fire Hydrant (Left)", "Lift your knee out to the side with control.", "01:24"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Text("Steps")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(.white.opacity(0.72))
                    .clipShape(Capsule())
                Text("Details")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReelplayOnboardingTheme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(4)
            .background(Color(hex: 0xEFE4D8).opacity(0.55))
            .clipShape(Capsule())

            ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [Color(hex: 0x6B523D), Color(hex: 0xC49B78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 38)
                        .overlay(Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.white.opacity(0.7)))

                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ReelplayOnboardingTheme.black)
                        .frame(width: 28, height: 28)
                        .background(Color(hex: 0xEFE2D2))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.0)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ReelplayOnboardingTheme.black)
                            .lineLimit(1)
                        Text(step.1)
                            .font(.caption)
                            .foregroundStyle(ReelplayOnboardingTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(step.2)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ReelplayOnboardingTheme.muted)
                }
                .padding(8)
                .background(.white.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ReelplayOnboardingTheme.divider))
            }
        }
        .padding(10)
        .background(ReelplayOnboardingTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.5)))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct OnboardingStepList: View {
    let activeStep: Int
    private let steps = [
        ("Import reel", "square.and.arrow.down"),
        ("Process video", "sparkles"),
        ("See step breakdown", "list.bullet"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 14) {
                    Image(systemName: step.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(index == self.activeStep ? ReelplayOnboardingTheme.accent : ReelplayOnboardingTheme.muted.opacity(0.48))
                        .frame(width: 28, height: 28)
                        .background(index == self.activeStep ? Color(hex: 0xF0DFC7) : Color.black.opacity(0.035))
                        .clipShape(Circle())

                    Text(step.0)
                        .font(.footnote.weight(index == self.activeStep ? .bold : .medium))
                        .foregroundStyle(ReelplayOnboardingTheme.black)

                    Spacer()

                    if index == self.activeStep {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ReelplayOnboardingTheme.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color(hex: 0xF0DFC7))
                            .clipShape(Capsule())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ReelplayOnboardingTheme.accent)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(index == self.activeStep ? Color(hex: 0xF7E9D8).opacity(0.72) : .clear)

                if index < self.steps.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .background(ReelplayOnboardingTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ReelplayOnboardingTheme.divider))
    }
}

private struct ReelplayOnboardingDots: View {
    let count: Int
    let selectedPage: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<self.count, id: \.self) { index in
                Circle()
                    .fill(index == self.selectedPage ? ReelplayOnboardingTheme.black : Color.black.opacity(0.2))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

struct 💁OnBoardingHandle: ViewModifier {
    @EnvironmentObject var app: 📱AppModel
    func body(content: Content) -> some View {
        content
#if !os(visionOS)
            .task {
                if NSUbiquitousKeyValueStore.default.dictionaryRepresentation.isEmpty {
                    self.app.sheet = .onboarding
                }
            }
#endif
    }
}

private struct 💁HowToHomeScreen: View {
    var body: some View {
        List {
            Self.StepByStepSection()
            Self.AppleSupportLinkSection()
        }
        .navigationTitle("Home screen widget")
    }
    private struct StepByStepSection: View {
        private let steps: [Int: LocalizedStringKey] = [
            1: "Touch and hold the home screen until the + button appears, then tap + button.",
            2: #"Select "LockInNote"."#,
            3: "Select or drag the widgets that you want to add to the Home Screen.",
            4: "When you're finished, tap the Done button."
        ]
        var body: some View {
            Section {
                ForEach(1 ... 4, id: \.self) { ⓘndex in
                    HStack {
                        Label {
                            if let ⓣext = self.steps[ⓘndex] {
                                Text(ⓣext)
                            }
                        } icon: {
                            Text(verbatim: "\(ⓘndex).")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                        }
                        Spacer()
                        Image("WidgetGuide/HomeScreen/\(ⓘndex)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120)
                            .padding(4)
                    }
                }
            }
        }
    }
    private struct AppleSupportLinkSection: View {
        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: URL(string: "https://support.apple.com/HT207122")!) {
                        Label("How to add and edit widgets on your iPhone", systemImage: "link")
                    }
                    HStack {
                        Spacer()
                        Text(verbatim: "https://support.apple.com/HT207122")
                            .font(.caption2.italic())
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Apple Support Page Link")
            }
            .headerProminence(.increased)
        }
    }
}

private struct 💁HowToLockScreen: View {
    var body: some View {
        List {
            Self.StepByStepSection()
            Self.AppleSupportLinkSection()
        }
        .navigationTitle("Lock screen widget")
    }
    private struct StepByStepSection: View {
        private let steps: [Int: LocalizedStringKey] = [
            1: "Touch and hold the Lock Screen until the Customize button appears, then tap Customize.",
            2: "Select Lock Screen.",
            3: "Tap Add Widgets.",
            4: "Tap or drag the widgets that you want to add to the Lock Screen.",
            5: "When you're finished, tap the close button, then tap Done."
        ]
        var body: some View {
            Section {
                ForEach(1 ... 5, id: \.self) { ⓘndex in
                    HStack {
                        Label {
                            if let ⓣext = self.steps[ⓘndex] {
                                Text(ⓣext)
                            }
                        } icon: {
                            Text(verbatim: "\(ⓘndex).")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                        }
                        Spacer()
                        Image("WidgetGuide/LockScreen/\(ⓘndex)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120)
                            .padding(4)
                    }
                }
            }
        }
    }
    private struct AppleSupportLinkSection: View {
        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: URL(string: "https://support.apple.com/HT207122")!) {
                        Label("How to add and edit widgets on your iPhone", systemImage: "link")
                    }
                    HStack {
                        Spacer()
                        Text(verbatim: "https://support.apple.com/HT207122")
                            .font(.caption2.italic())
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: URL(string: "https://support.apple.com/guide/iphone/create-a-custom-lock-screen-iph4d0e6c351/ios")!) {
                        Label("Create a custom iPhone Lock Screen", systemImage: "link")
                    }
                    HStack {
                        Spacer()
                        Text(verbatim: "https://support.apple.com/guide/iphone/create-a-custom-lock-screen-iph4d0e6c351/ios")
                            .font(.caption2.italic())
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Apple Support Page Link")
            }
            .headerProminence(.increased)
        }
    }
}

private struct 💁ICloudSyncSection: View {
    var body: some View {
        NavigationLink {
            List {
                Section {
                    Label("Sync data between devices by iCloud.", systemImage: "icloud")
                    HStack {
                        Text("""
                        ・Note text
                        ・Note title
                        ・Customize options
                        """)
                        .font(.subheadline)
                        Spacer()
                        Image(.concept)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120)
                    }
                    #if os(iOS)
                    .padding(8)
                    #endif
                } footer: {
                    Text("It takes few minutes to sync data to other device's widget on background. At the latest, the changes will be applied in about 20 minutes.")
                }
            }
            .navigationTitle("iCloud sync")
        } label: {
            Label("iCloud sync", systemImage: "icloud")
        }
    }
}
