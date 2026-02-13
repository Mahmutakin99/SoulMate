import UIKit
import UserNotifications
#if canImport(GiphyUISDK)
import GiphyUISDK
#endif
#if canImport(SDWebImage)
import SDWebImage
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseManager.shared.configureCoreIfNeeded()
        configureImageCaching()
        UNUserNotificationCenter.current().delegate = self
        #if canImport(GiphyUISDK)
        DispatchQueue.main.async {
            Giphy.configure(apiKey: "WYImRjePDCRWrDKSDjaBwR41Lh7OcMp0")
        }
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebaseManager.shared.updateAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed (non-fatal): \(error.localizedDescription)")
        #endif
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }

    private func configureImageCaching() {
        #if canImport(SDWebImage)
        let cacheConfig = SDImageCache.shared.config
        cacheConfig.maxMemoryCost = AppConfiguration.ImageCache.maxMemoryCostBytes
        cacheConfig.maxDiskSize = AppConfiguration.ImageCache.maxDiskSizeBytes
        cacheConfig.maxDiskAge = AppConfiguration.ImageCache.maxDiskAgeSeconds
        cacheConfig.shouldUseWeakMemoryCache = true
        #endif
    }

}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
