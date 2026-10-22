# اپ چت (Flutter + Node.js)

ثبت‌نام و ورود با نام کاربری و رمز عبور، چت لحظه‌ای، ظاهر شبیه تلگرام/iOS.

```
chatapp/
├── server/   ← سرور (Node.js) – اول روی Termux، بعد روی هاست
├── app/      ← اپ Flutter
└── .github/workflows/build.yml  ← بیلد APK در گیت‌هاب
```

## ۱) اجرای سرور روی Termux

```bash
pkg update && pkg upgrade
pkg install nodejs git
cd server
npm install
node server.js
```

سرور روی پورت 3000 بالا میاد. برای اینکه Termux وقتی صفحه خاموشه بسته نشه:

```bash
termux-wake-lock
```

داده‌ها در `server/data.json` ذخیره میشن (برای انتقال به سرور جدید فقط همین فایل رو کپی کنید).

## ۲) بیلد اپ در گیت‌هاب

1. یه ریپوی جدید در GitHub بسازید و کل این پروژه رو push کنید (شاخه `main`).
2. تب **Actions** ← workflow به اسم **Build Android APK** خودکار اجرا میشه (یا دستی Run workflow بزنید).
3. بعد از تموم شدن، پایین صفحه‌ی اجرا در بخش **Artifacts** فایل `chat-apk` رو دانلود کنید، زیپ رو باز کنید و `app-release.apk` رو نصب کنید.

## ۳) وصل کردن اپ به سرور

- **سرور روی همون گوشی (Termux):** آدرس پیش‌فرض اپ `http://127.0.0.1:3000` هست، نیازی به تغییر نیست.
- **سرور روی گوشی/کامپیوتر دیگه در همون Wi-Fi:** در صفحه ورود روی آیکن ⚙️ بزنید و آدرس رو بنویسید، مثلاً `http://192.168.1.20:3000` (آی‌پی با `ifconfig` در Termux پیدا میشه).

## ۴) انتقال به سرور واقعی (بعداً)

1. پوشه `server` رو روی سرور کپی کنید، `npm install` و `node server.js` (برای دائمی شدن: `npm i -g pm2 && pm2 start server.js`).
2. حتماً جلوی سرور HTTPS بذارید (مثلاً با Caddy یا Nginx + Let's Encrypt)، چون رمز عبورها از شبکه رد میشن.
3. در اپ آدرس سرور رو به `https://your-domain.com` تغییر بدید (اپ دوباره بیلد نمی‌خواد).

## API (برای اطلاع)

| مسیر | کار |
|---|---|
| `POST /register`, `POST /login` | ثبت‌نام / ورود (برمی‌گردونه token) |
| `GET /users?q=` | جستجوی کاربران |
| `GET /chats` | لیست گفتگوها |
| `GET /messages/:id`, `POST /messages/:id` | تاریخچه / ارسال پیام |
| `ws://.../ws?token=` | دریافت لحظه‌ای پیام |
