# SoulMate Push Functions

Bu klasör, Realtime Database'e yazılan yeni mesajlar için otomatik FCM push gönderen Cloud Function içerir.

## Kurulum

1. Firebase CLI kur:
   - `npm i -g firebase-tools`
2. Giriş yap:
   - `firebase login`
3. Projeyi seç:
   - `firebase use <your-firebase-project-id>`
4. Bağımlılıkları kur:
   - `cd firebase/functions && npm install`
5. Deploy et:
   - `npm run deploy`

## Trigger

- Yol: `/chats/{chatId}/messages/{messageId}`
- Olay: yeni mesaj oluşturulunca
- Alıcı: `recipientID` kullanıcısının `users/<uid>/fcmToken` değeri

## Gönderilen payload

- `data.enc_body`: şifreli mesaj içeriği (`payload`)
- `data.sender_id`: gönderen kullanıcı ID
- `data.chat_id`: chat kimliği
- `aps.mutable-content = 1` (Notification Service Extension çalışsın diye)
