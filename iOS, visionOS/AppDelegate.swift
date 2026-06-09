import UIKit

final class ReelplayAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ReelBackgroundSession.sessionIdentifier else {
            completionHandler()
            return
        }
        // Touching the singleton re-creates the URLSession with the same identifier,
        // which causes iOS to replay pending events to the delegate. Store the
        // handler so urlSessionDidFinishEvents can call it when all events are delivered.
        ReelBackgroundSession.shared.backgroundCompletionHandler = completionHandler
    }
}
