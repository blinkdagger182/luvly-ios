import UIKit
import UserNotifications

final class ReelplayAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // ─── Background URLSession (reel import) ────────────────────────────────

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ReelBackgroundSession.sessionIdentifier else {
            completionHandler()
            return
        }
        ReelBackgroundSession.shared.backgroundCompletionHandler = completionHandler
    }

    // ─── Push notification registration ─────────────────────────────────────

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .reelplayDidReceivePushToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    // ─── Foreground notification display ────────────────────────────────────

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // ─── Notification tap handling ───────────────────────────────────────────

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .reelplayDidTapPushNotification, object: nil, userInfo: userInfo)
        completionHandler()
    }
}

extension Notification.Name {
    static let reelplayDidReceivePushToken      = Notification.Name("reelplay.pushToken")
    static let reelplayDidTapPushNotification   = Notification.Name("reelplay.pushTap")
}
