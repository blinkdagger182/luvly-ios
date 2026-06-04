import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: 📱AppModel
    var body: some View {
        ReelplayRootView()
        .sheet(item: self.$app.sheet) {
            switch $0 {
                case .customize(let ⓝoteFamily):
                    🎚️CustomizeMenu()
                        .modifier(📋AddNoteToEnvironment(ⓝoteFamily))
                case .onboarding:
                    💁HowToOnBoarding()
                case .ad:
                    📣ADSheet()
            }
        }
        .onOpenURL { self.app.handle($0) }
        .modifier(💬RequestUserReview())
        .modifier(🪧ReloadWidgetsOnActive())
        .environmentObject(self.app.inAppPurchaseModel)
    }
}
