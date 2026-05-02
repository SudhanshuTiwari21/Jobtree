# Testing Without Twilio and Firebase Config

**Short answer: Yes — the app is ready for testing** without configuring Twilio (SMS OTP + calls) or Firebase. Core flows work; only real SMS, real calls, and push notifications are disabled or stubbed.

---

## What you need configured

| Item | Required for testing? | Notes |
|------|------------------------|--------|
| **Backend URL** | ✅ Yes | App must point at your API (e.g. EC2 or localhost). |
| **Database** | ✅ Yes | `DATABASE_URL` (PostgreSQL/Neon). Run migrations. |
| **JWT_SECRET** | ✅ Yes | Backend needs it for auth; use a strong value in production. |
| **AWS S3** (optional) | For profile photo upload | Presigned uploads; can skip and test rest of app. |
| **Twilio** | ❌ No | In **development**, OTP is printed in the server log. In **production** without Twilio, OTP SMS is not delivered. Call masking runs in **dry-run** without Twilio. |
| **Firebase (Flutter)** | ❌ No | App starts; push and token registration are skipped. |

---

## Backend: without Twilio

### OTP / Login

- **Development** (`NODE_ENV` not `production`): OTP is **not sent by SMS**. The backend **logs the OTP to the server console** (terminal/logs). Use that code in the app to log in.
- **Production without Twilio**: A warning is printed on startup. OTPs are **not** sent by SMS and are **not** printed to the console. Configure `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_PHONE_NUMBER` (or `TWILIO_SMS_FROM`) for real SMS.

**How to test login:** Run backend with `NODE_ENV=development` (or leave it unset). After requesting OTP, check backend logs and enter the code in the app.

### Call masking (no Twilio / dry-run)

- Without Twilio credentials, the backend runs in **dry-run** for calls: the API still creates a session, but **no real call** is placed.

---

## Flutter app: without Firebase config

- On startup, if `firebase_options.dart` is not configured, the error is **caught** in `main()` and the app **continues**.
- **What does not work without Firebase:** push (FCM), device token registration, deep links from notification taps.
- **What still works:** other flows, including auth with dev OTP from server logs.

When you need push, run `flutterfire configure` and add the generated `firebase_options.dart`.

---

## Minimal backend `.env` for testing

```env
NODE_ENV=development
PORT=3000
DATABASE_URL=postgresql://user:password@host/jobtree?sslmode=require
JWT_SECRET=your-secret-at-least-32-characters-long
```

Optional when you go live:

- **Twilio** — SMS OTP and masked calls (see `backend/.env.example` and `ENV_REFERENCE.md`).
- **AWS S3** — profile photo upload.
- **Firebase** on the backend — push from server (if used).

---

## Summary

| Area | Without Twilio (dev) | Without Twilio (prod) | Without Firebase (app) |
|------|------------------------|-------------------------|-------------------------|
| App starts | ✅ | ✅ | ✅ |
| Login (OTP) | ✅ (OTP in server logs) | ❌ real SMS | ✅ |
| Jobs, applications, candidates | ✅ | If API works | ✅ |
| Real SMS / calls | ❌ | Need Twilio | — |
| Push | — | — | ❌ |

For day-to-day testing, use **`NODE_ENV=development`** and read OTPs from the backend terminal. Add Twilio for production SMS and calls.
