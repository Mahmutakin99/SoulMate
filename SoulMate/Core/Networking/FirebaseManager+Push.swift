import Foundation
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

extension FirebaseManager {
    func configureIfNeeded() {
        configureCoreIfNeeded()
        configureMessagingDelegateIfNeeded()
    }

    func configureCoreIfNeeded() {
        #if canImport(FirebaseCore)
        configurationLock.lock()
        defer { configurationLock.unlock() }

        if isCoreConfigured {
            return
        }

        FirebaseApp.configure()
        isCoreConfigured = true
        #endif
    }

    func configureMessagingDelegateIfNeeded() {
        configureCoreIfNeeded()
        #if canImport(FirebaseMessaging)
        configurationLock.lock()
        if isMessagingDelegateConfigured {
            configurationLock.unlock()
            syncFCMTokenIfPossible()
            return
        }
        isMessagingDelegateConfigured = true
        configurationLock.unlock()
        Messaging.messaging().delegate = self
        syncFCMTokenIfPossible()
        #endif
    }

    func requestPushAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                #if DEBUG
                print("Bildirim izni alınamadı: \(error.localizedDescription)")
                #endif
            }
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestPushAuthorizationIfNeeded() {
        #if targetEnvironment(simulator)
        #if DEBUG
        print("Push registration skipped on simulator.")
        #endif
        return
        #else
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: pushPromptRequestedKey) {
            return
        }
        defaults.set(true, forKey: pushPromptRequestedKey)
        requestPushAuthorization()
        #endif
    }

    func updateAPNSToken(_ deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        configurationLock.lock()
        hasAPNSToken = true
        configurationLock.unlock()
        Messaging.messaging().apnsToken = deviceToken
        syncFCMTokenIfPossible()
        #endif
    }

    func syncFCMTokenIfPossible() {
        #if canImport(FirebaseMessaging) && !targetEnvironment(simulator)
        guard isFirebaseConfigured() else { return }
        guard let uid = currentUserID() else { return }
        let now = Date()

        configurationLock.lock()
        if !hasAPNSToken || isSyncingFCMToken {
            configurationLock.unlock()
            return
        }
        if let lastSync = lastFCMTokenSyncAt, now.timeIntervalSince(lastSync) < minimumFCMTokenSyncInterval {
            configurationLock.unlock()
            return
        }
        isSyncingFCMToken = true
        lastFCMTokenSyncAt = now
        configurationLock.unlock()

        Messaging.messaging().token { [weak self] token, error in
            guard let self else { return }
            self.configurationLock.lock()
            self.isSyncingFCMToken = false
            self.configurationLock.unlock()

            if let error {
                let message = error.localizedDescription.lowercased()
                if !(message.contains("no apns token") || message.contains("apns")) {
                    #if DEBUG
                    print("FCM token alınamadı: \(error.localizedDescription)")
                    #endif
                }
                return
            }

            guard let token, !token.isEmpty else { return }
            self.updateFCMToken(uid: uid, token: token)
        }
        #endif
    }
}

#if canImport(FirebaseMessaging)
extension FirebaseManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken,
              let uid = currentUserID() else { return }
        updateFCMToken(uid: uid, token: fcmToken)
    }
}
#endif
