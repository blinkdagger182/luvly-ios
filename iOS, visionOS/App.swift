import SwiftUI

@main
struct iOS_and_visionOS_App: App {
    @UIApplicationDelegateAdaptor(ReelplayAppDelegate.self) var delegate
    @StateObject private var model = 📱AppModel()
    
    var body: some Scene {
        
        WindowGroup {
            ContentView()
                .environmentObject(self.model)
        }
#if os(visionOS)
        .defaultSize(width: 450, height: 320)
#endif
        
    }
}
