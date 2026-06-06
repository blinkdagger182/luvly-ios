import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: 📱AppModel
    var body: some View {
        ReelplayRootView()
        .modifier(💁OnBoardingHandle())
        .sheet(item: self.standardSheet) {
            switch $0 {
                case .customize(let ⓝoteFamily):
                    🎚️CustomizeMenu()
                        .modifier(📋AddNoteToEnvironment(ⓝoteFamily))
                case .ad:
                    📣ADSheet()
                case .onboarding:
                    EmptyView()
            }
        }
        .fullScreenCover(item: self.onboardingSheet) { _ in
            💁HowToOnBoarding()
        }
        .onOpenURL { self.app.handle($0) }
        .modifier(💬RequestUserReview())
        .modifier(🪧ReloadWidgetsOnActive())
        .environmentObject(self.app.inAppPurchaseModel)
    }

    private var standardSheet: Binding<💬Sheet?> {
        Binding {
            switch self.app.sheet {
                case .customize, .ad:
                    self.app.sheet
                case .onboarding, .none:
                    nil
            }
        } set: { newValue in
            if newValue == nil {
                self.app.sheet = nil
            }
        }
    }

    private var onboardingSheet: Binding<💬Sheet?> {
        Binding {
            switch self.app.sheet {
                case .onboarding:
                    self.app.sheet
                case .customize, .ad, .none:
                    nil
            }
        } set: { newValue in
            if newValue == nil {
                self.app.sheet = nil
            }
        }
    }
}
