# Jobtree — Implementation Audit

**Last updated:** From codebase review.  
**Scope:** Backend (Node/Express/PostgreSQL), Flutter app (iOS/Android).

---

## 1. Backend — Fully Implemented

| Area | What's done |
|------|-------------|
| **Auth** | OTP send/verify (Twilio SMS), JWT access/refresh, logout, role switch (owner ↔ seeker). Seeker refresh tokens stored. |
| **Salon (owner)** | Profile CRUD, completion %, S3 media (presign, save, delete), profile endpoints. |
| **Jobs** | Create, read, update, delete; my-jobs; search (public); public job view; job completion %. |
| **Applications** | Seeker apply (with duplicate check); get by seeker; get by job (owner). Uses `applications` table. |
| **Owner candidate management** | Get candidates per job (with filters); update status (applied → shortlisted → interview → hired/rejected); audit log. |
| **Interviews** | Schedule, reschedule, complete; interview_events log; get interview details (owner + seeker). |
| **Calls (Twilio)** | Initiate masked call; webhooks (connect, status); call_sessions; rate limit (3 calls/candidate/day). |
| **Push notifications** | FCM via `pushService.js`: device register/unregister, sendNotification (throttle, retry, token deactivation), logging to `push_notification_log`. Triggers: new_application, shortlisted, interview, hired, rejected, interview_scheduled, interview_rescheduled. |
| **In-app notifications (owner)** | `notifications` table, preferences, get/list, mark read, read-all. Stored per salon. |
| **Notification read API** | GET /notifications, unread-count, PATCH :id/read, read-all — work for both owner and seeker (from `push_notification_log`). |
| **Support** | Create ticket (owner), get support config (phone/WhatsApp from env). Owner-only. |
| **Seeker** | Profile, preferences, job feed, apply, applications list, interview details. |
| **Database** | Migrations for salons, jobs, applications, application_status_logs, interview_events, call_sessions, notifications, notification_preferences, push_tokens, user_devices, push_notification_log, support_tickets, analytics_events, seeker_*, otp_requests, refresh_tokens, salon_media, etc. |

---

## 2. Backend — Placeholders / Partial / Missing

| Item | Status | Notes |
|------|--------|------|
| **notificationService.sendPushNotification** | Stub | Only logs; real push is in `pushService.js` (FCM). Owner in-app notifications still use `notificationService`; push delivery uses `pushService`. |
| **notificationTriggers.notifyCandidateApplied** | Unused | Never called from `applicationService`. New application push is sent from `applicationService.apply` via `pushService.sendNotification`. |
| **Interview reminder (owner)** | TODO | In `interviewService.js`: after “complete interview”, TODO to notify owner (hire/reject). No implementation. |
| **Interview reminder (scheduled time passed)** | Missing | No cron/scheduler. Comment in code: “If interview_scheduled_at < NOW() and interview_status = 'scheduled' → send reminder to owner”. |
| **Call analytics** | TODO | callMaskingService: track call_initiated, call_completed, duration, conversion not implemented. |
| **Monetization / premium** | Placeholder | Call limit (3/candidate/day) exists; no “premium” tier, no payment, no unlimited calls. |
| **Support config** | Env/placeholder | `getSupportConfig()` returns `SUPPORT_PHONE` / `WHATSAPP_SUPPORT` from env or hardcoded fallbacks. |
| **Support for seekers** | Owner-only | Support routes use `authenticate` (owner). Seekers cannot create tickets via API unless a seeker support route is added. |
| **Analytics** | Minimal | `analytics_events` table exists. Only `notificationService` writes (NOTIFICATION_SENT, NOTIFICATION_OPENED). No dashboard, no job/call/application analytics. |
| **job_applications table** | Unused? | Migration creates it; app uses `applications` table everywhere. May be legacy. |

---

## 3. Flutter — Fully Implemented

| Area | What's done |
|------|-------------|
| **Onboarding & language** | Onboarding flow, language choice (EN/Hindi), persisted. |
| **Auth** | OTP send/verify, role selection, switch role, logout; token storage (secure + prefs). |
| **Owner flows** | Home (jobs list), create job, edit job, improve job (optional fields); from job card → View Job → CandidateListScreen (candidates, status, schedule/reschedule/complete interview, secure call); profile screen; support (call, create ticket). |
| **Seeker flows** | Home (job feed), apply, applications list, profile create/edit, preferences. |
| **Push** | Firebase init, FCM token, register/unregister with backend; deep links: owner → job (CandidateListScreen), seeker → applications tab. |
| **Notifications (API)** | Get list, unread count, mark read, read-all (from push log); owner also has preferences. |
| **Support** | Get support config (phone), call support, create ticket (owner token). |
| **API service** | Auth, salon, jobs, notifications, device (FCM), support, seeker, owner applications, calls, interview scheduling. |

---

## 4. Flutter — Placeholders / Missing

| Location / feature | Issue |
|--------------------|--------|
| **Seeker app bar notification bell** | `onPressed: () {}` — no navigation to notification center. |
| **Owner bottom nav: Candidates / Chat** | Tapping “Candidates” or “Chat” (when has candidates) does nothing; TODO: “Navigate to candidates/chat”. CandidateListScreen is only reached via job card “View Job”. |
| **Onboarding “Continue” (one step)** | `// TODO: Navigate to next step` — button does not advance flow. |
| **Improve Job flow** | `// TODO: Navigate to job details` — one place not wired. |
| **Photo picker** | `// TODO: Implement photo picker` (e.g. seeker or profile). |
| **Profile completion navigation** | `// TODO: Implement profile completion navigation`. |
| **Owner profile** | Several TODOs: upload photo, edit profile flow, progressive edit, photo upload, verification flow, pricing/plans, edit salon details; “Check actual status” for some status; “Placeholder for photos (TODO: Load actual photos from S3)”. |
| **Deep link (one screen)** | `// TODO: Handle deep link navigation` — may be redundant with PushNotificationService. |
| **Email** | `// TODO: Open email client` (e.g. support). |
| **Firebase** | `firebase_options.dart` is a stub until `flutterfire configure` is run. |

---

## 5. Summary Table

| Category | Implemented | Placeholder / Missing |
|----------|-------------|------------------------|
| **Auth (OTP, JWT, roles)** | ✅ | — |
| **Jobs & applications** | ✅ | — |
| **Interviews (schedule, reschedule, complete)** | ✅ | Interview reminder (owner + cron) |
| **Calls (Twilio masking)** | ✅ | Call analytics, premium/unlimited |
| **Push (FCM, triggers, device, log)** | ✅ | — |
| **Owner in-app notifications** | ✅ | Old push path in notificationService is stub |
| **Support (tickets, config)** | ✅ (owner) | Seeker support, real config source |
| **Owner app (jobs, candidates, profile, support)** | ✅ | Nav Candidates/Chat, profile TODOs, S3 photos in UI |
| **Seeker app (feed, apply, applications, profile)** | ✅ | Notification bell, photo picker |
| **Onboarding / profile / verification** | Partial | Several “next step” / verification / pricing TODOs |
| **Analytics** | Minimal (notification events only) | No dashboard, no call/job/application analytics |
| **Cron / background** | — | Interview reminder job |

---

## 6. Recommended Next Steps (priority)

1. **Flutter:** Wire notification bell (seeker) to notification list screen.
2. **Flutter:** Wire owner bottom nav “Candidates” (and optionally “Chat”) to a dedicated screen or CandidateListScreen by job.
3. **Flutter:** Fix onboarding “Continue” and any other “Navigate to next step” that blocks a critical path.
4. **Backend:** Add interview reminder (e.g. after “complete interview” + optional cron for past scheduled time).
5. **Backend:** Add seeker support route (or reuse ticket creation with seeker auth) if seekers should open tickets.
6. **Backend:** Either remove unused `notificationTriggers.notifyCandidateApplied` or integrate with push; consider deprecating `notificationService.sendPushNotification` in favor of `pushService` only for push.

Use this audit to track what’s production-ready vs what’s still placeholder or missing.
