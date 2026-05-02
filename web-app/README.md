# Jobtree Web (Next.js)

Production-oriented web client for the Jobtree API — phone OTP login, job seeker & salon owner flows, applications, interviews, masked calls, notifications, and owner support tickets.

## Behaviour notes

- **No in-app chat:** The backend has no chat/WebSocket API. Communication is **masked phone calls** (Twilio) plus **notifications**. Seeker Help shows a helpline number from env when set.
- **Dev server port:** `npm run dev` uses **port 3001** so it does not clash with the Node API on **3000**.
- **CORS:** The backend allows `http://localhost:3001` by default (see `backend/src/config/index.js`). Set `ALLOWED_ORIGINS` in production for your web domain.

## Setup

```bash
cd web-app
cp .env.example .env.local
# Edit NEXT_PUBLIC_API_URL — e.g. http://localhost:3000 or your EC2 / HTTPS URL (no trailing /api)
npm install
npm run dev
```

Open [http://localhost:3001](http://localhost:3001).

## Build

```bash
npm run build
npm start
```

## UX

Large tap targets, bilingual **English + Hindi** hints on primary screens, minimal copy for users with limited literacy.

## API mapping

All requests use `NEXT_PUBLIC_API_URL` + `/api/...` — same REST surface as the Flutter app (`auth`, `seeker`, `jobs`, `owner`, `calls`, `notifications`, `salon`, `support`).
