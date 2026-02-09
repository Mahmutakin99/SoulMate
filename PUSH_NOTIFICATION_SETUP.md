# SoulMate Push Notification Kurulumu (Adım Adım)

Bu repo tarafında push için kod tarafı hazırlandı:

- App launch'ta Firebase tek noktadan başlatılıyor.
- Chat'e giren kullanıcıda push izni bir kez isteniyor.
- APNs token -> FCM token -> Realtime DB `users/<uid>/fcmToken` senkronu yapılıyor.
- Notification Service Extension için dosyalar hazır:
  - `SoulMateNotificationService/NotificationService.swift`
  - `SoulMateNotificationService/Info.plist`
  - `SoulMateNotificationService/SoulMateNotificationService.entitlements`
- Mesaj geldiğinde otomatik push için Firebase Function eklendi:
  - `firebase/functions/index.js`

Aşağıdaki adımlar sadece senin panel/Xcode tarafında yapman gerekenlerdir.

## 1) Apple Developer ayarları

1. [Apple Developer](https://developer.apple.com/account) > Certificates, Identifiers & Profiles aç.
2. `Identifiers` içinde `com.MahmutAKIN.SoulMate` App ID'yi aç.
3. `Push Notifications` özelliğini aç.
4. `Keys` bölümünde yeni APNs Auth Key (`.p8`) oluştur.
5. `Key ID` ve `Team ID` değerlerini not al.

## 2) Firebase Cloud Messaging ayarı

1. Firebase Console > Project Settings > **Cloud Messaging**.
2. APNs Authentication Key alanına `.p8` dosyasını yükle.
3. Team ID ve Key ID gir.
4. Kaydet.

## 3) Xcode main app target capability ayarları

1. Xcode'da `SoulMate` app targetını aç.
2. `Signing & Capabilities` sekmesinde şunları kontrol et:
   - **Push Notifications**
   - **Background Modes** (`Remote notifications` işaretli)
   - **App Groups** (`group.com.MahmutAKIN.SoulMate`)
   - **Keychain Sharing** (`BQH8W6X63R.com.MahmutAKIN.SoulMate.shared`)
3. Provisioning profile'ı yeniden üretmen gerekebilir; Xcode'un otomatik güncellemesini bekle.

## 4) Notification Service Extension target ekleme (kritik)

Projede extension klasörü hazır, fakat Xcode targetını sen eklemelisin:

1. `File > New > Target...`
2. `Notification Service Extension` seç.
3. Product Name: `SoulMateNotificationService`
4. Bundle Identifier: `com.MahmutAKIN.SoulMate.NotificationService`
5. Target oluşunca aşağıdaki yolları ver:
   - `Info.plist`: `SoulMateNotificationService/Info.plist`
   - `Code Sign Entitlements`: `SoulMateNotificationService/SoulMateNotificationService.entitlements`
6. Extension target `Signing & Capabilities`:
   - **App Groups**: `group.com.MahmutAKIN.SoulMate`
   - **Keychain Sharing**: `BQH8W6X63R.com.MahmutAKIN.SoulMate.shared`
7. `NotificationService.swift` dosyasında target membership olarak extension target işaretli olsun.

## 5) Cloud Function deploy (mesajdan push üretmek için)

Bu adım yapılmazsa push otomatik oluşmaz.

1. Makinede Firebase CLI kur:
   - `npm i -g firebase-tools`
2. Login ol:
   - `firebase login`
3. Proje kökünde Firebase proje ID seç:
   - `firebase use <firebase-project-id>`
4. Function bağımlılıklarını kur:
   - `cd firebase/functions`
   - `npm install`
5. Deploy et:
   - `npm run deploy`

Function davranışı:

- Realtime DB path: `/chats/{chatId}/messages/{messageId}`
- Alıcı token path: `/users/{recipientID}/fcmToken`
- Push data:
  - `enc_body` (şifreli payload)
  - `sender_id`
  - `chat_id`
- `mutable-content = 1` ile extension'da local decrypt yapılır.

## 6) Test sırası

1. Uygulamayı **gerçek cihazda** çalıştır.
2. Giriş + eşleşme tamamla.
3. Chat ekranına gir (ilk sefer push izni sorulur).
4. İzin ver.
5. Realtime DB'de `users/<uid>/fcmToken` yazıldığını doğrula.
6. Bir cihazdan mesaj gönder.
7. Diğer cihazda push görünmeli ve body çözümlenmiş gelmeli.

## 7) Yaygın hatalar

- `aps-environment not found`
  - Push capability/provisioning eksik.
- Bildirim geliyor ama şifre çözülmüyor
  - Extension target yok veya App Group/Keychain Sharing eşleşmiyor.
- Token yazılmıyor
  - Kullanıcı chat akışına hiç girmemiş olabilir.
  - APNs kaydı cihazda başarısız olabilir.
