# SoulMate

SoulMate, yalnızca eşleşen iki kullanıcı arasında özel iletişim için tasarlanmış güvenli bir iOS mesajlaşma uygulamasıdır.

Programmatic UIKit mimarisi, local-first mesaj akışı, uçtan uca şifreleme (E2EE) ve tek cihaz oturum kilidi ile gerçek kullanım senaryolarına odaklanır.

## Öne Çıkan Özellikler

- 1:1 (çift odaklı) sohbet deneyimi
- Uçtan uca şifreleme (CryptoKit: ECDH + HKDF-SHA256 + AES-GCM)
- Local-first mesaj akışı (SQLite3)
- Gönderildi / iletildi / okundu durumu (tick + read receipt)
- Mesaj reaksiyonları (emoji)
- Heartbeat (kalp atışı) etkileşimi
- Tek cihaz oturum kilidi (session lock)
- Push bildirimleri + Notification Service Extension ile şifreli içerik işleme

## Mimari Özeti

```text
iOS (UIKit)
  -> LocalMessageStore (SQLite3)
  -> MessageSyncService (queue/retry/sync)
  -> Firebase Realtime Database (mesaj/event akışı)
  -> Firebase Functions (ack/read/reaction/session/pairing)
  -> Firebase Messaging (push)
```

## Teknoloji Yığını

- Dil: Swift 5+
- UI: UIKit (Storyboard yok)
- Yerel Veri: SQLite3
- Backend: Firebase Auth, Realtime Database, Cloud Functions (2nd gen), Firebase Messaging
- Şifreleme: CryptoKit
- Diğer: SDWebImage, GiphyUISDK (legacy GIF gösterimi için)

## Hızlı Başlangıç

Detaylı kurulum için: [`SETUP_GUIDE.md`](SETUP_GUIDE.md)

Özet akış:

1. Repoyu klonla.
2. `SoulMate/Core/Files/GoogleService-Info.plist` dosyasını Firebase projenle oluştur.
3. Xcode'da `SoulMate.xcodeproj` aç, signing/capabilities ayarlarını tamamla.
4. Backend deploy et:
   - `npx firebase-tools@latest deploy --project <FIREBASE_PROJECT_ID> --only functions,database`
5. Uygulamayı gerçek cihazda çalıştır.

## Public Repo ve Gizli Bilgiler

Aşağıdaki dosyalar bilinçli olarak Git dışında tutulur:

- `.firebaserc`
- `SoulMate/Core/Files/GoogleService-Info.plist`
- `firebase/functions/.env*`
- `firebase/functions/.runtimeconfig.json`

Örnek konfigürasyon dosyası:

- `SoulMate/Core/Files/GoogleService-Info.plist.example`

## Proje Yapısı

```text
SoulMate/
├── SoulMate/                      # Ana iOS uygulaması (Core, Controllers, ViewModels, Models, Views)
├── SoulMateNotificationService/   # Bildirim extension (decrypt pipeline)
├── SoulMateWidget/                # Widget extension
├── firebase/functions/            # Cloud Functions (Node.js 22)
├── database.rules.json            # Realtime Database güvenlik kuralları
├── SETUP_GUIDE.md                 # Kurulum ve operasyon rehberi
└── README.md
```

## Operasyonel Notlar

- Functions runtime: Node.js 22
- Varsayılan callable bölgesi: `europe-west1`
- Realtime Database kuralları deploy edilmeden canlı kullanım yapılmamalı
- Personal Team ile APNs capability sınırlı olabilir; push doğrulamasını mümkünse ücretli Apple Developer hesabıyla yap

## Katkı ve Bakım

- Pull request öncesi local build alın:
  - `xcodebuild -project SoulMate.xcodeproj -scheme SoulMate -destination 'generic/platform=iOS Simulator' build`
- Backend değişikliklerinde functions + rules birlikte deploy edin.

---

Geliştirici: Mahmut AKIN
