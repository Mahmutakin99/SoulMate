# SoulMate

SoulMate, çiftler için özel iletişime odaklanan, modern ve güvenli bir iOS mesajlaşma uygulamasıdır. Programmatic UIKit yaklaşımıyla geliştirilmiş olup; kimlik doğrulama, eşleşme yönetimi, uçtan uca şifreleme (E2EE) ve tek cihaz oturum kilidi gibi gelişmiş özellikler sunar.

## Özellikler

*   **Güvenli Mesajlaşma**: Mesajlar cihazda şifrelenir ve sadece alıcı tarafından çözülebilir. Sunucuda asla düz metin saklanmaz.
*   **Çift Odaklı Tasarım**: Sadece eşleştiğiniz kişiyle iletişim kurabilirsiniz.
*   **Local-First Mimari**: Mesajlar önce cihaz veritabanına kaydedilir, internet bağlantısı olmasa bile geçmişe erişim sağlar.
*   **Tek Cihaz Kilidi**: Aynı hesabın birden fazla cihazda eşzamanlı kullanılmasını engelleyerek güvenlik sağlar.
*   **Gelişmiş Medya Desteği**: Text, Emoji ve özel "Kalp Atışı" mesajları.
*   **Bildirimler**: Arka planda şifre çözme yeteneğine sahip zengin bildirimler.

## Kullanılan Teknolojiler

*   **Dil**: Swift 5+
*   **Arayüz**: UIKit (Programmatic, Storyboard yok)
*   **Backend**: Firebase (Auth, Realtime Database, Cloud Functions 2nd Gen, Messaging)
*   **Veritabanı**: SQLite3 (Yerel depolama için)
*   **Şifreleme**: CryptoKit (ECDH, HKDF-SHA256, AES-GCM)
*   **Kütüphaneler**: SDWebImage, GiphyUISDK

## Kurulum ve Başlangıç

Projenin kurulumu, API anahtarlarının yapılandırılması ve backend deploy işlemleri için detaylı bir rehber hazırladık.

Lütfen kurulum adımları için aşağıdaki dokümanı inceleyin:

👉 **[SoulMate Kurulum ve Yapılandırma Rehberi (SETUP_GUIDE.md)](SETUP_GUIDE.md)**

## Proje Yapısı

```text
SoulMate/
├── SoulMate/                  # Ana uygulama kodu (Controllers, ViewModels, Core)
├── SoulMateWidget/            # iOS Widget extension
├── SoulMateNotificationService/# Bildirim şifre çözme servisi
├── firebase/functions/        # Backend mantığı (Node.js)
├── database.rules.json        # Veritabanı güvenlik kuralları
└── SETUP_GUIDE.md             # Kurulum rehberi
```

## Güvenlik Notları

*   **Uçtan Uca Şifreleme**: Mesaj içerikleri sunucuya gitmeden önce cihazda şifrelenir.
*   **Anahtar Yönetimi**: Özel anahtarlar Keychain'de saklanır (`AccessibleAfterFirstUnlockThisDeviceOnly`).
*   **Geçici Depolama**: Sunucu sadece şifreli mesajları geçici olarak tutar, teslim edildikten sonra silinir.

---
Geliştirici: Mahmut AKIN
