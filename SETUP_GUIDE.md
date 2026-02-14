# SoulMate Kurulum ve Yapılandırma Rehberi

Bu rehber, SoulMate iOS projesini sıfırdan kurmak, yapılandırmak ve dağıtmak için gerekli tüm adımları içerir.

## İçindekiler

1.  [Gereksinimler](#1-gereksinimler)
2.  [Proje Kurulumu](#2-proje-kurulumu)
3.  [Firebase Yapılandırması](#3-firebase-yapılandırması)
4.  [Push Notification Kurulumu](#4-push-notification-kurulumu)
    *   [Apple Developer Ayarları](#41-apple-developer-ayarları)
    *   [Firebase Cloud Messaging](#42-firebase-cloud-messaging)
    *   [Xcode Ayarları](#43-xcode-main-app-target-capability-ayarları)
    *   [Notification Service Extension](#44-notification-service-extension-target-ekleme)
5.  [Backend (Cloud Functions & Rules)](#5-backend-cloud-functions--rules)
6.  [Widget Kurulumu](#6-widget-kurulumu)
7.  [Sıkça Sorulan Sorular ve Hata Çözümleri](#7-sıkça-sorulan-sorular-ve-hata-çözümleri)

---

## 1. Gereksinimler

*   **Xcode**: En güncel sürüm (iOS 17+ SDK desteği için).
*   **CocoaPods** veya **Swift Package Manager** (Proje SPM kullanmaktadır).
*   **Firebase CLI**: `npm i -g firebase-tools`
*   **Node.js**: Sürüm 20 (Cloud Functions için).
*   **Apple Developer Hesabı**: Push notification ve App Group özellikleri için gereklidir.

---

## 2. Proje Kurulumu

1.  Repoyu klonlayın:
    ```bash
    git clone https://github.com/MahmutAKIN/SoulMate.git
    cd SoulMate
    ```

2.  Swift Paketlerini Yükleyin:
    Xcode üzerinden `File > Add Package Dependencies` menüsünü kullanarak aşağıdaki paketlerin yüklü olduğundan emin olun:
    *   `firebase-ios-sdk` (Auth, Database, Messaging, Crashlytics) (github.com/firebase/firebase-ios-sdk)
    *   `giphy-ios-sdk` (GiphyUISDK) (github.com/firebase/firebase-ios-sdk) ! Kullanabilmek API anahtarı almanız gereklidir. --> https://developers.giphy.com/dashboard/?create=true
    *   `SDWebImage` (github.com/SDWebImage/SDWebImage.git)

---

## 3. Firebase Yapılandırması

SoulMate, backend olarak tamamen Firebase kullanır.

1.  **Firebase Projesi Oluşturun**: [Firebase Console](https://console.firebase.google.com/) üzerinden yeni bir proje oluşturun.
2.  **Servisleri Aktifleştirin**:
    *   **Authentication**: Email/Password sağlayıcısını açın.
    *   **Realtime Database**: Veritabanını oluşturun (bölge: `europe-west1` önerilir).
    *   **Cloud Messaging**: Push bildirimleri için.
    *   **Functions**: Backend mantığı için (Blaze planı gerektirir).
    *   **Storage**: (Opsiyonel) Profil fotoğrafları için gerekirse.
3.  **iOS Uygulamasını Ekleyin**:
    *   Paket adı: `com.MahmutAKIN.SoulMate` (kendi bundle ID'nizi kullanın).
    *   İndirdiğiniz `GoogleService-Info.plist` dosyasını `SoulMate/SoulMate/` klasörüne taşıyın ve Xcode projesine ekleyin.
4.  **API Key Yapılandırması**:
    *   `AppDelegate.swift` içinde Giphy API key'inizi güncelleyin:
        ```swift
        Giphy.configure(apiKey: "VARSA_KEY_BURAYA")
        ```

---

## 4. Push Notification Kurulumu

Anlık mesajlaşma deneyimi için Push Notification kurulumu kritiktir.

### 4.1. Apple Developer Ayarları

1.  [Apple Developer Portal](https://developer.apple.com/account) > **Certificates, Identifiers & Profiles**'a gidin.
2.  **Identifiers** altında uygulamanızın App ID'sini bulun.
3.  **Push Notifications** özelliğini (capability) etkinleştirin.
4.  **Keys** bölümünde yeni bir APNs Auth Key (`.p8`) oluşturun.
5.  Key dosyasını indirin ve `Key ID` ile `Team ID` değerlerini not edin.

### 4.2. Firebase Cloud Messaging

1.  Firebase Console > Project Settings > **Cloud Messaging** sekmesine gidin.
2.  **Apple app configuration** altında APNs Authentication Key alanına `.p8` dosyanızı yükleyin.
3.  `Key ID` ve `Team ID` bilgilerinizi girin.

### 4.3. Xcode Main App Target Capability Ayarları

Xcode'da `SoulMate` target'ı seçili iken **Signing & Capabilities** sekmesinde şu özellikleri ekleyin:

*   **Push Notifications**
*   **Background Modes**: `Remote notifications` seçeneğini işaretleyin.
*   **App Groups**: `group.com.MahmutAKIN.SoulMate` (kendi group ID'niz).
*   **Keychain Sharing**: `BQH8W6X63R.com.MahmutAKIN.SoulMate.shared` (kendi team ID'nizle).

### 4.4. Notification Service Extension Target Ekleme

Zengin bildirimler ve şifreli mesajların arka planda çözülmesi (decrypt) için bu adım zorunludur.

1.  Xcode: `File > New > Target...` > **Notification Service Extension**.
2.  İsim: `SoulMateNotificationService`.
3.  Aşağıdaki dosyaların bu target'a ait olduğundan emin olun (File Inspector > Target Membership):
    *   `SoulMateNotificationService/NotificationService.swift`
4.  **Capabilities**:
    *   Extension target için de **App Groups** ve **Keychain Sharing** yeteneklerini ana uygulama ile birebir aynı olacak şekilde ekleyin. Bu, anahtar paylaşımı ve veri okuma için şarttır.
5.  **Info.plist**: `SoulMateNotificationService/Info.plist` dosyasının doğru yapılandırıldığını kontrol edin.

---

## 5. Backend (Cloud Functions & Rules)

Güvenlik kuralları ve sunucu taraflı işlemler için deploy gereklidir.

### 5.1. Realtime Database Kuralları

```bash
firebase deploy --only database
```
Bu komut `database.rules.json` dosyasını Firebase'e yükler.

### 5.2. Cloud Functions

Fonksiyonlar; eşleşme istekleri, oturum kilidi ve mesaj ACK mekanizması için kullanılır.

1.  Dizine gidin:
    ```bash
    cd firebase/functions
    ```
2.  Bağımlılıkları yükleyin:
    ```bash
    npm install
    ```
3.  Deploy edin:
    ```bash
    npm run deploy
    # Veya
    firebase deploy --only functions
    ```

**Önemli Functions:**
*   `sendEncryptedMessagePush`: Yeni mesaj geldiğinde tetiklenir ve push gönderir.
*   `acquireSessionLock`: Tek cihaz oturumunu yönetir.
*   `cleanupExpiredTransientMessages`: Teslim edilmeyen eski mesajları temizler.

---

## 6. Widget Kurulumu

Ana ekranda partner durumunu görmek için Widget target'ı eklenmiştir.

1.  Xcode: `File > New > Target...` > **Widget Extension**.
2.  Dosyaları `SoulMateWidget` klasöründen target'a dahil edin.
3.  Widget target'ına da **App Groups** eklemeyi unutmayın (`group.com.MahmutAKIN.SoulMate`).
4.  `SoulMateWidget.swift` dosyasının giriş noktası (entry point) olduğunu doğrulayın.

---

## 7. Sıkça Sorulan Sorular ve Hata Çözümleri

### "aps-environment not found" Hatası
Provisioning profile veya Entitlements hatasıdır. Xcode'da Push Notification capability'sinin açık olduğundan ve provision dosyasının güncel olduğundan emin olun.

### Bildirim Geliyor Ama İçerik "Mesaj" Olarak Kalıyor / Şifre Çözülmüyor
Notification Service Extension çalışmıyor veya anahtarlara erişemiyor demektir.
*   App Group ve Keychain Sharing ayarlarının **hem App hem Extension** target'larında aynı olduğundan emin olun.
*   Deployment Target sürümünün cihazınızla uyumlu olduğunu kontrol edin.

### "createUnpairRequest failed: NOT FOUND"
Cloud Function deploy edilmemiş. `firebase deploy --only functions` komutunu çalıştırın.

### "Permission Denied" (Firebase)
Genellikle `database.rules.json` dosyasının deploy edilmemesinden veya kullanıcının auth durumunun (token) geçerliliğini yitirmesinden kaynaklanır. Kuralları tekrar deploy edin ve uygulamada yeniden oturum açın.
