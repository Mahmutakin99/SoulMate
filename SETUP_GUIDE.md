# SoulMate Kurulum ve Operasyon Rehberi

Bu doküman, SoulMate projesini sıfırdan kurmak, Firebase tarafını ayağa kaldırmak, iOS imzalama/capability ayarlarını tamamlamak ve üretim öncesi doğrulama yapmak için hazırlanmıştır.

## İçindekiler

1. Gereksinimler
2. Repo Kurulumu
3. Firebase Proje Hazırlığı
4. iOS Konfigürasyonu (`GoogleService-Info.plist`)
5. Xcode Signing & Capabilities
6. Notification Service Extension Ayarları
7. Cloud Functions ve Rules Deploy
8. İlk Çalıştırma Kontrol Listesi
9. Public Repo Güvenlik Kontrolü
10. Sık Karşılaşılan Hatalar ve Çözümler

## 1) Gereksinimler

- macOS + güncel Xcode
- Node.js 22 (Functions runtime ile uyumlu)
- `npm`
- Firebase CLI
  - `npm i -g firebase-tools`
- Apple Developer hesabı
  - Push testleri için ücretli Developer Program gerekir (Personal Team kısıtlıdır)

## 2) Repo Kurulumu

```bash
git clone <REPO_URL>
cd SoulMate
```

Projede Swift Package Manager kullanılır. Xcode açıldığında paketler otomatik çözülür.

Xcode ile aç:

```bash
open SoulMate.xcodeproj
```

## 3) Firebase Proje Hazırlığı

Firebase Console'da yeni proje oluştur ve aşağıdaki servisleri aç:

- Authentication (Email/Password)
- Realtime Database
- Cloud Functions
- Cloud Messaging

Önerilen bölge:

- Functions: `europe-west1`
- Realtime Database: proje/altyapı ihtiyacına göre, gecikme açısından yakın bölge

## 4) iOS Konfigürasyonu (`GoogleService-Info.plist`)

1. Firebase projesine iOS app ekle.
2. Bundle Identifier olarak kendi değerini kullan.
3. `GoogleService-Info.plist` dosyasını indir.
4. Dosyayı şu konuma koy:

- `SoulMate/Core/Files/GoogleService-Info.plist`

Notlar:

- Bu dosya `.gitignore` nedeniyle repoya commit edilmez.
- Örnek şablon mevcut:
  - `SoulMate/Core/Files/GoogleService-Info.plist.example`

## 5) Xcode Signing & Capabilities

`TARGETS > SoulMate > Signing & Capabilities` altında kontrol et:

- Team seçili olmalı
- Bundle Identifier Firebase'deki iOS app ile birebir aynı olmalı
- Capabilities:
  - Push Notifications
  - Background Modes -> Remote notifications
  - App Groups
  - Keychain Sharing

Önemli:

- `AppConfiguration.swift` içindeki şu değerler capability tarafıyla uyumlu olmalı:
  - `AppConfiguration.appGroupIdentifier`
  - `AppConfiguration.keychainAccessGroup`

## 6) Notification Service Extension Ayarları

`SoulMateNotificationService` target'ında:

- Team/Signing doğru
- App Groups ana target ile aynı
- Keychain Sharing ana target ile aynı
- `Info.plist` doğru target membership altında

Bu extension, push payload içindeki şifreli gövdeyi işleyebilmek için kritiktir.

## 7) Cloud Functions ve Rules Deploy

Önce functions bağımlılıkları:

```bash
cd firebase/functions
npm install
cd ../..
```

Deploy (önerilen):

```bash
npx firebase-tools@latest deploy --project <FIREBASE_PROJECT_ID> --only functions,database
```

Notlar:

- Silinecek eski function uyarısı gelirse, lokal kaynakta artık yoksa `y` ile temizleyebilirsin.
- Deploy sonrası Firebase Console'dan function listesi ve database rules yayın zamanını kontrol et.

## 8) İlk Çalıştırma Kontrol Listesi

1. Uygulama açılıyor ve auth ekranı geliyor.
2. Kayıt/giriş çalışıyor.
3. Pair request gönderme/yanıtlama çalışıyor.
4. Mesaj gönder/al çalışıyor.
5. Tick/read/reaction akışı çalışıyor.
6. Uygulama yeniden açıldığında local mesaj geçmişi görünüyor.
7. Gerçek cihazda push token alınıyor (APNs capability doğruysa).

## 9) Public Repo Güvenlik Kontrolü

Public'e açmadan önce şu dosyaların git tarafından izlenmediğini doğrula:

- `.firebaserc`
- `SoulMate/Core/Files/GoogleService-Info.plist`
- `firebase/functions/.env*`
- `firebase/functions/.runtimeconfig.json`

Hızlı kontrol:

```bash
git check-ignore -v .firebaserc SoulMate/Core/Files/GoogleService-Info.plist
```

Ek güvenlik önerileri:

- Firebase API key'lerini iOS bundle kısıtıyla sınırla.
- Geçmişte hassas anahtar commit edildiyse rotate/revoke et.

## 10) Sık Karşılaşılan Hatalar ve Çözümler

### A) `aps-environment` entitlement hatası

Neden:

- Push capability/provision profile uyumsuz
- Personal Team ile push entitlement alınamaması

Çözüm:

1. Push Notifications capability kontrol et.
2. Provisioning profile yenile.
3. Ücretli Apple Developer hesabı ile yeniden sign et.

### B) `Declining request for FCM Token since no APNS Token specified`

Neden:

- Simülatörde APNs token yok
- Gerçek cihazda push capability eksik

Çözüm:

- Simülatörde bu log normaldir.
- Gerçek cihazda capability + profile doğrula.

### C) `permission_denied` (Realtime Database)

Neden:

- Rules deploy edilmemiş
- Kullanıcı auth değil / token geçersiz
- Pairing koşulu sağlanmıyor

Çözüm:

1. `database.rules.json` deploy et.
2. Uygulamada yeniden login ol.
3. Pairing durumunu kontrol et.

### D) `ackMessageStored ... INTERNAL`

Neden:

- Functions kodu ile deploy edilen sürüm arasında uyumsuzluk
- Eski/yarım kalmış function sürümü

Çözüm:

1. `functions,database` birlikte yeniden deploy et.
2. Firebase Console'dan function loglarını incele.
3. Eski/unused function uyarılarını temizle.

### E) `Couldn't find firebase-functions package`

Neden:

- `firebase/functions/node_modules` eksik

Çözüm:

```bash
cd firebase/functions
npm install
```

## Faydalı Komutlar

iOS build doğrulama:

```bash
xcodebuild -project SoulMate.xcodeproj -scheme SoulMate -destination 'generic/platform=iOS Simulator' build
```

Functions emulator:

```bash
cd firebase/functions
npm run serve
```

---

Bu rehber canlıda güvenli ve tekrarlanabilir kurulum hedefiyle hazırlanmıştır. Ortam bazlı farklar (bundle id, team id, proje id) için ilgili alanları kendi altyapına göre güncelle.
