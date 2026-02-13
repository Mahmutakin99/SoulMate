# SoulMate

SoulMate, çiftler için özel iletişime odaklanan, programmatic UIKit ile geliştirilmiş bir iOS uygulamasıdır.

Bu repo, yalnızca bir sohbet ekranı değil; kimlik doğrulama, profil tamamlama, istek tabanlı eşleşme yönetimi, tek cihaz oturum kilidi, local-first mesajlaşma ve uçtan uca şifreleme (E2EE) akışlarını birlikte içerir.

## İçindekiler

- Proje Hedefi
- Kullanılan Teknolojiler
- Ürün Özellikleri
- Uygulama Akışı
- Mesajların Nasıl Saklandığı
- Şifreleme ve Şifre Çözme Modeli
- Tek Cihaz Oturum Kilidi
- Firebase Mimarisi
- Proje Yapısı
- Kurulum
- Deploy
- Test ve Doğrulama
- Troubleshooting
- Güvenlik ve Gizlilik Notları

## Proje Hedefi

SoulMate’in temel hedefleri:

- Çiftlere sade ve odaklı bir mesajlaşma deneyimi sunmak
- Mesaj içeriğini istemci tarafında şifreleyerek sunucuda düz metin saklamamak
- Bulut maliyetini düşürmek için cloud’u kalıcı arşiv yerine geçici teslim kuyruğu olarak kullanmak
- Eşleşme ve eşleşme kaldırma işlemlerini kullanıcı onayı ile yönetmek
- Aynı hesabın birden fazla cihazda eşzamanlı açık kalmasını engellemek

## Kullanılan Teknolojiler

- Swift
- UIKit (Storyboard kullanılmıyor, UI tamamen kod ile)
- Firebase Auth
- Firebase Realtime Database
- Firebase Functions (2nd Gen)
- Firebase Messaging (FCM/APNs)
- Firebase Crashlytics
- CryptoKit
- SQLite3
- SDWebImage
- GiphyUISDK
- Live Activities (uygun target/plist ayarlarıyla)

Minimum hedef sürüm proje target’larına göre değişebilir; güncel değerler için `SoulMate.xcodeproj/project.pbxproj` içindeki `IPHONEOS_DEPLOYMENT_TARGET` değerlerini kontrol edin.

## Ürün Özellikleri

- Email/şifre ile kayıt ve giriş
- Kayıtta zorunlu ad/soyad toplama
- Eski hesaplar için profil tamamlama adımı
- 6 haneli kodla eşleşme isteği gönderme
- Gelen ve giden istek kutusu
- Eşleşme ve eşleşme kaldırma isteklerini kabul/reddetme
- Chat: text, emoji, GIF, gizli mesaj, kalp atışı
- Emoji barı aç/kapat
- Mesafe ve ilişki durumunu sidebar’da gösterme
- Profil butonunda bekleyen istek sayısı badge’i
- Splash ekranı ve kullanıcı tercihine göre kapatabilme
- Pairing ekranından güvenli çıkış (onaylı)
- Türkçe ve İngilizce çoklu dil desteği (`Localizable.xcstrings`)

## Uygulama Akışı

`AppFlowCoordinator` açılışta kullanıcıyı şu sırayla route eder:

1. Giriş yoksa `Auth`
2. Giriş var ama profil eksikse `ProfileCompletion`
3. Giriş var ama eşleşme yoksa `Pairing`
4. Giriş var ve karşılıklı eşleşme varsa `Chat`

Ek davranışlar:

- Persisted oturum varsa kullanıcıya tekrar login sorulmaz.
- Partnerlik bozulursa Chat ekranı Pairing’e geri yönlenir.
- Launch öncesinde session lock doğrulaması yapılır.

## Mesajların Nasıl Saklandığı

Bu projede mesajlar local-first modelle çalışır:

1. Mesaj önce cihazdaki SQLite store’a yazılır.
2. Sonra şifreli envelope olarak Firebase’e gönderilir.
3. Alıcı envelope’u alır, cihaz içinde decrypt eder, local store’a yazar.
4. Alıcı `ackMessageStored` callable ile “mesajı localde sakladım” ACK’i gönderir.
5. ACK sonrası ilgili cloud mesaj silinir.
6. ACK’siz kalan cloud mesajlar scheduled cleanup ile 7 gün sonra temizlenir.

Bu yüzden cloud tarafı kalıcı geçmiş değil, geçici teslim katmanı gibi kullanılır.

### Local veritabanı ayrıntısı

Local store dosyası:

- `Application Support/LocalMessageQueue/local_messages.sqlite`

Tablo:

- `local_messages`

Önemli kolonlar:

- `id` (primary key)
- `chat_id`
- `sender_id`
- `recipient_id`
- `sent_at`
- `payload_type`
- `payload_value`
- `is_secret`
- `direction` (`incoming` veya `outgoing`)
- `upload_state` (`pendingUpload`, `uploaded`, `failed`)
- `created_at`

İndeksler:

- `(chat_id, sent_at DESC)`
- `(chat_id, id)`
- `(upload_state, created_at)`

Performans için statement cache ve batch insert transaction kullanılır.

## Şifreleme ve Şifre Çözme Modeli

Bu projede mesaj içeriklerinin şifrelenmesi ve çözülmesi cihaz içinde yapılır.

Kullanılan yapı:

- Kimlik anahtarı: `Curve25519.KeyAgreement.PrivateKey`
- Anahtar anlaşması: ECDH (`sharedSecretFromKeyAgreement`)
- Anahtar türetme: HKDF-SHA256
- Mesaj şifreleme: `AES.GCM`

### Anahtar yönetimi

- Kullanıcının kimlik private key’i cihaz Keychain’inde tutulur.
- Partner bazlı shared key, `crypto.shared.<partnerUID>` hesabı ile Keychain’de saklanır.
- Keychain erişilebilirlik seviyesi: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

### Şifreleme akışı

1. Gönderim payload’ı JSON encode edilir (`ChatPayload`).
2. Payload, partner için türetilmiş shared key ile AES.GCM kullanılarak şifrelenir.
3. `sealedBox.combined` Base64’e çevrilir.
4. Firebase’e yalnızca bu ciphertext envelope yazılır.

### Şifre çözme akışı

1. Cloud’dan gelen ciphertext Base64 decode edilir.
2. AES.GCM ile cihaz içinde açılır.
3. JSON decode ile payload elde edilir.
4. UI ve local store buna göre güncellenir.

### Sunucu tarafı neyi görür

Sunucu plaintext mesaj içeriğini çözmez. Realtime Database’de saklanan içerik şifreli payload’dır.

Ancak metadata düz metin olarak bulunur:

- `senderID`
- `recipientID`
- `sentAt`
- `keyVersion`

Bu model “içerik gizliliği” sağlar, metadata gizliliği sağlamaz.

## Tek Cihaz Oturum Kilidi

Aynı hesabın birden fazla cihazda eşzamanlı açık kalmasını engellemek için `sessionLocks/{uid}` kullanılır.

Lock payload:

- `installationID`
- `platform` (`ios`)
- `deviceName`
- `appVersion`
- `acquiredAt`
- `updatedAt`

Akış:

1. Login sonrası `acquireSessionLock` çağrılır.
2. Farklı bir installation aktifse giriş reddedilir.
3. Launch’ta persisted session için tekrar validate/acquire yapılır.
4. Çıkışta önce `releaseSessionLock` çağrılır.
5. Release başarısızsa çıkış engellenir (network zorunlu politika).

Bu iterasyonda otomatik recovery yoktur. Cihaz kaybı/bozulması durumunda lock manuel temizlenmelidir.

## Firebase Mimarisi

### Realtime Database path’leri

- `users`
- `pairCodes`
- `relationshipRequests`
- `sessionLocks`
- `chats`
- `events`

### Functions

Callable:

- `createPairRequest` (`europe-west1`)
- `respondPairRequest` (`europe-west1`)
- `createUnpairRequest` (`europe-west1`)
- `respondUnpairRequest` (`europe-west1`)
- `acquireSessionLock` (`europe-west1`)
- `releaseSessionLock` (`europe-west1`)
- `ackMessageStored` (`europe-west1`)
- `deleteConversationForUnpair` (`europe-west1`)

Trigger/Scheduled:

- `sendEncryptedMessagePush` (DB trigger, `us-central1`)
- `cleanupExpiredTransientMessages` (scheduled)

## Proje Yapısı

```text
SoulMate/
├── SoulMate/
│   ├── Controllers/
│   ├── ViewModels/
│   ├── Models/
│   ├── Views/
│   ├── Resources/
│   └── Core/
│       ├── Config/
│       ├── Files/
│       ├── Flow/
│       ├── Networking/
│       ├── Security/
│       └── Utilities/
├── SoulMateWidget/
├── SoulMateNotificationService/
├── firebase/functions/
├── database.rules.json
├── SETUP.md
├── PUSH_NOTIFICATION_SETUP.md
└── SMOKE_CHECKLIST.md
```

## Kurulum

1. Firebase iOS config dosyasını ekleyin:

- `SoulMate/GoogleService-Info.plist`

2. Firebase Console’da şu servisleri açın:

- Authentication (Email/Password)
- Realtime Database
- Cloud Messaging
- Functions (2nd Gen)

3. Xcode’da capability kontrolü yapın:

- Push Notifications
- Background Modes (remote notifications)
- App Groups
- Keychain Sharing

## Deploy

### Realtime rules

```bash
cd /Users/gladius/Desktop/SoulMate
firebase deploy --only database --project <firebase-project-id>
```

### Functions

```bash
cd /Users/gladius/Desktop/SoulMate/firebase/functions
npm install

cd /Users/gladius/Desktop/SoulMate
firebase deploy --only functions --project <firebase-project-id>
firebase functions:list --project <firebase-project-id>
```

## Test ve Doğrulama

Detaylı checklist:

- [`SMOKE_CHECKLIST.md`](SMOKE_CHECKLIST.md)

Kritik testler:

- Login/Signup + profile completion akışı
- Pair request ve unpair request kabul/reddet
- Unpair sonrası local ve cloud temizliği
- Aynı hesapla ikinci cihaz login engeli
- İlk cihaz çıkışı sonrası ikinci cihazın giriş yapabilmesi
- Gönderilen mesajın alıcıda local store’a yazılıp ACK sonrası cloud’dan düşmesi

## Troubleshooting

### `createUnpairRequest failed: NOT FOUND`

Fonksiyon deploy edilmemiş veya yanlış projeye deploy edilmiştir.

```bash
firebase functions:list --project <firebase-project-id>
```

### `Permission Denied`

Genelde rules deploy edilmemesi veya karşılıklı eşleşme koşulunun sağlanmamasından kaynaklanır.

```bash
firebase deploy --only database --project <firebase-project-id>
```

### `No APNS token specified before fetching FCM Token`

Simülatörde normaldir. Gerçek cihazda APNs/Capability kurulumunu kontrol edin.

### `CryptoKitError`

Çoğunlukla anahtar uyumsuzluğu veya eşleşme/partner state değişimi kaynaklıdır.

Öneri:

1. İki tarafın pairing state’ini kontrol edin.
2. Gerekirse her iki kullanıcıda oturumu yenileyin.
3. Yeniden eşleşip tekrar deneyin.

### Session lock nedeniyle giriş engeli

Hesap başka cihazda açık görünüp yeni cihaz giremiyorsa:

1. Eski cihazdan normal çıkış yapın.
2. Eski cihaza erişim yoksa `sessionLocks/{uid}` kaydını manuel temizleyin.

## Güvenlik ve Gizlilik Notları

- Mesaj şifreleme/şifre çözme cihaz içinde yapılır.
- Sunucu plaintext mesaj içeriklerini çözmez.
- Cloud’da yalnızca geçici şifreli teslim verisi tutulur.
- Local geçmiş cihazda saklanır ve hızlı açılış sağlar.
- Local SQLite bu aşamada ayrıca dosya seviyesinde şifrelenmiyor.
- Gizli mesaj gibi UI özellikleri kriptografik modelden ayrı sunum katmanı davranışıdır.

## Ek Dokümanlar

- [SETUP.md](SETUP.md)
- [PUSH_NOTIFICATION_SETUP.md](PUSH_NOTIFICATION_SETUP.md)
- [SMOKE_CHECKLIST.md](SMOKE_CHECKLIST.md)
