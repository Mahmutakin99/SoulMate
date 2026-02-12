# SoulMate Setup Guide

## 1) Add Swift Package Dependencies
Add these packages in Xcode (`File > Add Package Dependencies`):

- `https://github.com/firebase/firebase-ios-sdk`
  - Products: `FirebaseAuth`, `FirebaseDatabase`, `FirebaseMessaging`, `FirebaseCore`
- `https://github.com/Giphy/giphy-ios-sdk`
  - Product: `GiphyUISDK`
- `https://github.com/SDWebImage/SDWebImage`
  - Product: `SDWebImage`

## 2) Firebase Configuration
1. Add `GoogleService-Info.plist` to `/Users/gladius/Desktop/SoulMate/SoulMate`.
2. Enable in Firebase Console:
   - Authentication (Email/Password)
   - Realtime Database
   - Cloud Messaging
3. Publish the rules from `/Users/gladius/Desktop/SoulMate/database.rules.json`.
4. Giphy API key kontrolü:
   - `/Users/gladius/Desktop/SoulMate/SoulMate/Core/Files/AppDelegate.swift` içinde
   - `Giphy.configure(apiKey: "...")`

## 3) App Groups
The app target already contains `/Users/gladius/Desktop/SoulMate/SoulMate/SoulMate.entitlements` with:

- `group.com.MahmutAKIN.SoulMate`
- `BQH8W6X63R.com.MahmutAKIN.SoulMate.shared` (Keychain Sharing)

Enable the same App Group in all extension targets (widget + notification service).

## 4) Widget Target
1. Create an iOS Widget Extension target.
2. Add files from `/Users/gladius/Desktop/SoulMate/SoulMateWidget` to that target.
3. Ensure `SoulMateWidget.swift` is the widget extension entry point.
4. Add App Group capability to the widget target.

## 5) Notification Service Extension
1. Create a Notification Service Extension target.
2. Add `/Users/gladius/Desktop/SoulMate/SoulMateNotificationService/NotificationService.swift` to that target.
3. Add App Group capability to the extension target.
4. Add Keychain Sharing capability to the extension target.
4. Configure FCM payload with encrypted fields:
   - `enc_body`
   - `sender_id`
   - `chat_id`

Detaylı push kurulumu için:
- `/Users/gladius/Desktop/SoulMate/PUSH_NOTIFICATION_SETUP.md`

## 6) URL Scheme (Optional)
For Live Activity deep links (`soulmate://chat`), add the URL scheme in target settings.

## 7) Security Notes
- Private key + shared keys are stored in Keychain.
- Message payloads are encrypted with AES-256-GCM before Firebase writes.
- Pairing is considered active only when both users point `partnerID` to each other.
