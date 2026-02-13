# SoulMate Smoke Checklist

Bu liste hızlı sürüm doğrulaması içindir. `P0` maddeleri geçmeden build paylaşılmamalı.

## Test Öncesi Hazırlık
- [ ] İki hesap hazır: `A` ve `B`
- [ ] İki cihaz hazır: tercihen 1 gerçek cihaz + 1 simülatör
- [ ] Her iki cihazda da uygulama temiz açılış aldı
- [ ] Firebase Console açık (Realtime Database + Functions)

## P0 - Kritik Akışlar

### 1. Açılış ve Oturum
- [ ] Uygulama açılıyor, crash yok
- [ ] Giriş yapılmamış kullanıcı `Auth` ekranına gidiyor
- [ ] Giriş yapılmış kullanıcı tekrar login istemeden devam ediyor
- [ ] Eşleşme yoksa `Pairing`, eşleşme varsa `Chat` açılıyor

### 2. Kayıt / Giriş
- [ ] Kayıtta ad/soyad/email/şifre zorunlu
- [ ] Login başarılı
- [ ] Yanlış şifre/email’de doğru hata mesajı gösteriliyor

### 3. İstek Tabanlı Eşleşme
- [ ] `A` -> `B` pair isteği atabiliyor
- [ ] `B` gelen istekte kimden geldiğini görüyor
- [ ] `B` kabul edince iki tarafta eşleşme tamamlanıyor
- [ ] Partneri olan kullanıcıya yeni pair isteği atılamıyor

### 4. Mesajlaşma (Temel)
- [ ] Text mesaj çift yönlü geliyor
- [ ] Emoji mesaj çalışıyor
- [ ] GIF mesaj çalışıyor
- [ ] Secret mesaj açılabiliyor
- [ ] Heartbeat çalışıyor

### 5. Unpair Request + Mesaj Silme
- [ ] Unpair isteği gönderiliyor
- [ ] Karşı taraf kabul etmeden mesajlar silinmiyor
- [ ] Karşı taraf kabul edince iki tarafta eşleşme bitiyor
- [ ] Kabul sonrası chat ekranı temizleniyor ve Pairing’e yönleniyor
- [ ] Firebase’de ilgili `/chats/<chatID>` ve `/events/<chatID>` silinmiş
- [ ] Local geçmiş de temizlenmiş (tekrar eşleşmede eski konuşma görünmüyor)

### 6. İstek Badge
- [ ] Gelen pending istek olunca sağ üst profil/hesap ikonunda kırmızı badge görünüyor
- [ ] Sayı doğru artıyor/azalıyor
- [ ] İstek çözülünce badge kayboluyor

### 7. Pairing Ekranında Çıkış
- [ ] Pairing ekranında `Çıkış Yap` butonu var
- [ ] Onay diyaloğu geliyor
- [ ] Onay sonrası `Auth` ekranına dönüyor

## P1 - UI ve Kullanılabilirlik

### 8. Chat Kullanım Deneyimi
- [ ] Send’e basınca klavye kapanmıyor
- [ ] Emoji bar gizle/göster düzgün çalışıyor
- [ ] Uygulama yeniden açıldığında emoji görünürlük tercihi korunuyor
- [ ] Sidebar aç/kapa akıcı

### 9. Splash Tercihi
- [ ] Oturum detaylarından splash aç/kapat değiştirilebiliyor
- [ ] Uygulama tekrar açılınca tercih korunuyor

### 10. Uyarı/Log Temizliği
- [ ] `already presenting UIAlertController` uyarısı yok
- [ ] Sürekli `permission_denied` spam yok
- [ ] AutoLayout unsatisfiable constraint spam yok

## P1 - Performans Hızlı Kontrol
- [ ] 200+ mesajda chat açılışı akıcı
- [ ] Yukarı kaydırmada eski mesaj yükleme takılmadan çalışıyor
- [ ] GIF yoğun ekranda kaydırma kabul edilebilir
- [ ] 10 dk kullanımda bellek artışı anormal değil (Xcode Memory Gauge)

## Hızlı Sonuç Formatı
- [ ] `P0: PASS/FAIL`
- [ ] `P1: PASS/FAIL`
- [ ] Bulunan bug listesi (adım + beklenen + gerçekleşen + ekran görüntüsü/log)

