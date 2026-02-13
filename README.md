# SoulMate

SoulMate, çiftler için özel ve güvenli mesajlaşma odaklı, UIKit tabanlı bir iOS uygulamasıdır.

Uygulama mimarisi şu temel hedefler üzerine kuruludur:
- Güvenli kanal: uçtan uca anahtar anlaşması + AES.GCM şifreleme
- Kontrollü ilişki yönetimi: istek tabanlı eşleşme/ayrılma akışları
- Performans: local-first mesaj geçmişi + Firebase’de geçici teslim kuyruğu
- Temiz akış: Auth, Profile Completion, Pairing, Chat ekranlarının ayrıştırılması

## Öne Çıkan Özellikler

- E-posta/şifre ile kayıt ve giriş
- Zorunlu ad/soyad profil tamamlama akışı
- 6 haneli kod ile eşleşme isteği
- Gelen-giden istek kutusu (pair / unpair request)
- Chat ekranında text, emoji, GIF, secret mesaj ve heartbeat
- send butonunda SF Symbol efekt animasyonu
- emoji barı aç/kapat
- sağ sidebar (güvenli kanal, eşleşme, mesafe, mood)
- Profil ikonunda gelen istek badge sayacı
- Splash ekranı (kullanıcı tercihi ile aç/kapat)
- Pairing ekranında güvenli çıkış (onay diyalogu)
- Türkçe + İngilizce yerelleştirme (`Localizable.xcstrings`)

## Uygulama Akışı

`AppFlowCoordinator` açılışta kullanıcıyı otomatik yönlendirir:

1. Giriş yok -> `Auth`
2. Giriş var, ad/soyad eksik -> `ProfileCompletion`
3. Giriş var, eşleşme yok / karşılıklı eşleşme tamamlanmamış -> `Pairing`
4. Giriş var, karşılıklı eşleşme var -> `Chat`

Not:
- Kullanıcı tekrar giriş yapmak zorunda kalmaz.
- Partnerlik bozulursa Chat ekranı Pairing’e geri route edilir.

## Mesajlaşma Mimarisi (Local-First + Ephemeral Cloud Queue)

Bu projede Firebase chat düğümü kalıcı arşiv gibi değil, geçici teslim kuyruğu olarak kullanılır:

1. Gönderen mesajı önce local store’a yazar.
2. Sonra şifreli envelope Firebase’e gönderilir.
3. Alıcı envelope’u alır, decrypt eder, local store’a yazar.
4. Local yazım sonrası `ackMessageStored` callable çağrılır.
5. ACK başarılıysa cloud mesajı silinir.
6. ACK alamayan mesajlar için scheduled cleanup ile 7 gün sonra cloud temizliği yapılır.

Böylece:
- UI açılışında geçmiş local’den hızlı gelir.
- Cloud storage maliyeti düşer.
- Offline/yeniden deneme davranışı daha deterministik olur.

## Proje Yapısı

```text
SoulMate/
├── SoulMate/                       # iOS app target (UIKit)
│   ├── Controllers/
│   ├── ViewModels/
│   ├── Core/
│   │   ├── Flow/
│   │   ├── Networking/
│   │   ├── Security/
│   │   ├── Utilities/
│   │   └── Config/
│   ├── Models/
│   ├── Views/
│   └── Resources/
├── SoulMateWidget/                 # Widget kaynakları
├── SoulMateNotificationService/    # Notification Service Extension kaynakları
├── firebase/functions/             # Cloud Functions (Node.js 20)
├── database.rules.json             # Realtime Database kuralları
├── SETUP.md
├── PUSH_NOTIFICATION_SETUP.md
└── SMOKE_CHECKLIST.md
```

## Teknoloji ve Gereksinimler

- iOS deployment target: `18.6`
- Swift + UIKit (Storyboard yok, programmatic UI)
- Firebase Auth
- Firebase Realtime Database
- Firebase Functions
- Firebase Messaging
- Firebase Crashlytics
- GiphyUISDK
- SDWebImage
- Functions runtime: Node.js `20`

## Hızlı Kurulum

### 1) Firebase proje dosyasını ekle

`GoogleService-Info.plist` dosyasını şu klasöre ekleyin:

`/Users/gladius/Desktop/SoulMate/SoulMate`

### 2) Firebase tarafını hazırlayın

Firebase Console’da şunlar açık olmalı:
- Authentication (Email/Password)
- Realtime Database
- Cloud Messaging
- Cloud Functions (2nd gen)

### 3) Realtime Database kurallarını yayınlayın

```bash
cd /Users/gladius/Desktop/SoulMate
firebase deploy --only database --project <firebase-project-id>
```

### 4) Cloud Functions deploy edin

```bash
cd /Users/gladius/Desktop/SoulMate/firebase/functions
npm install

cd /Users/gladius/Desktop/SoulMate
firebase deploy --only functions --project <firebase-project-id>
firebase functions:list --project <firebase-project-id>
```

Beklenen fonksiyonlar:
- `createPairRequest` (`europe-west1`)
- `respondPairRequest` (`europe-west1`)
- `createUnpairRequest` (`europe-west1`)
- `respondUnpairRequest` (`europe-west1`)
- `ackMessageStored` (`europe-west1`)
- `cleanupExpiredTransientMessages` (scheduled)
- `deleteConversationForUnpair` (`europe-west1`)
- `sendEncryptedMessagePush` (Realtime DB trigger, `us-central1`)

### 5) Xcode’da açıp çalıştırın

```bash
cd /Users/gladius/Desktop/SoulMate
open SoulMate.xcodeproj
```

## Push Bildirimleri

Push kurulumunun detaylı adımları:

- [`/Users/gladius/Desktop/SoulMate/PUSH_NOTIFICATION_SETUP.md`](/Users/gladius/Desktop/SoulMate/PUSH_NOTIFICATION_SETUP.md)

Özet:
- APNs key Firebase Console’a yüklenmeli
- Main app + Notification Service extension capability’leri doğru olmalı
- App Group ve Keychain Sharing uyumlu olmalı

## Güvenlik Notları

- Kimlik anahtarı: `Curve25519.KeyAgreement`
- Ortak anahtar türetme: HKDF-SHA256
- Mesaj şifreleme: `AES.GCM`
- Anahtarlar Keychain’de saklanır
- Eşleşme aktif sayılma koşulu karşılıklıdır (`partnerID` iki tarafta da birbirini göstermeli)

## Yerelleştirme

- Tüm kullanıcı metinleri key tabanlı `xcstrings` üzerinden yönetilir:
- `/Users/gladius/Desktop/SoulMate/SoulMate/Resources/Localizable.xcstrings`
- Aktif diller: `tr`, `en`

## Test / Smoke

Hızlı sürüm doğrulama listesi:

- [`/Users/gladius/Desktop/SoulMate/SMOKE_CHECKLIST.md`](/Users/gladius/Desktop/SoulMate/SMOKE_CHECKLIST.md)

## Sık Karşılaşılan Sorunlar

### `createUnpairRequest failed: NOT FOUND`

Neden:
- Fonksiyon deploy edilmemiştir ya da yanlış projeye deploy edilmiştir.

Kontrol:
```bash
firebase functions:list --project <firebase-project-id>
```

### `Permission Denied` (`relationshipRequests`, `chats`, `events`, `users`)

Neden:
- `database.rules.json` deploy edilmemiştir.
- Eşleşme karşılıklı değildir.

Kontrol:
```bash
firebase deploy --only database --project <firebase-project-id>
```

### `No APNS token specified before fetching FCM Token`

Neden:
- Simülatörde APNS token yoktur (normal).
- Gerçek cihazda push capability/APNs kurulumu eksik olabilir.

### `CryptoKitError`

Neden:
- Eşleşme/anahtar senkronu bozulmuş olabilir.

Çözüm:
1. Her iki tarafta pairing durumunu kontrol edin.
2. Gerekirse çıkış yapıp tekrar giriş yapın.
3. Tekrar eşleşip test edin.

## Ek Dokümanlar

- Kurulum özeti: [`/Users/gladius/Desktop/SoulMate/SETUP.md`](/Users/gladius/Desktop/SoulMate/SETUP.md)
- Push kurulum: [`/Users/gladius/Desktop/SoulMate/PUSH_NOTIFICATION_SETUP.md`](/Users/gladius/Desktop/SoulMate/PUSH_NOTIFICATION_SETUP.md)
- Smoke test: [`/Users/gladius/Desktop/SoulMate/SMOKE_CHECKLIST.md`](/Users/gladius/Desktop/SoulMate/SMOKE_CHECKLIST.md)
