# Push Notification Refactor — Validation Report

**Scope:** Backend only.  
**Checks:** Single push service, logging, token invalidation, non-blocking, throttling, deep link, Firebase init.

---

## 1. No file imports `notificationService.sendPushNotification`

| Check | Result |
|-------|--------|
| Grep for `sendPushNotification` | **No matches** in codebase. |
| Grep for `getActivePushTokens` | **No matches** (stub helper removed). |
| `notificationService` usage | Only `createNotification`, `getPreferences`, `updatePreferences`, `registerPushToken` — no push delivery. |

**✔ Clean:** Stub removed; no references to `sendPushNotification`.

---

## 2. `pushService.js` is used everywhere for push

| Call site | Usage |
|-----------|--------|
| `applicationService.js` | `pushService.sendNotification(salonId, 'owner', …)` — new_application. |
| `ownerApplicationService.js` | `pushService.sendNotification(seekerId, 'seeker', …)` — shortlisted, interview, hired, rejected. |
| `interviewService.js` | `pushService.sendNotification(seekerId, 'seeker', …)` — interview_scheduled, interview_rescheduled. |
| `interviewReminderService.js` | `pushService.sendNotification(salonId, 'owner', …)` — interview_reminder. |
| `notificationService.js` | `pushService.sendNotification(salonId, 'owner', …)` for CANDIDATE_APPLIED, CANDIDATE_REPLIED, INTERVIEW_REMINDER. |
| `notificationRoutes.js` | `pushService` for getNotifications, getUnreadCount, markAsRead, markAllAsRead (read API, not send). |
| `deviceRoutes.js` | `pushService` for registerDevice, unregisterDevice, deactivateAllDevicesForUser. |

**✔ Clean:** All push delivery goes through `pushService.sendNotification`; no other module sends push.

---

## 3. `push_notification_log` entries on every push

| Step | Code path |
|------|-----------|
| Throttle / duplicate check | `shouldSendNotification()` → if `!allowed` return (no log). |
| Log before send | `logNotification(userId, userType, payload)` → `INSERT INTO push_notification_log` (line 137–144). |
| Mark sent | After FCM call, `markLogSent(logId)` sets `sent_at` (line 231). |

**✔ Clean:** Every push that passes the throttle results in one row in `push_notification_log`; `sent_at` is set when the send is performed. Attempts with no tokens or unconfigured FCM still get a row (with `sent_at` null unless/until logic is extended).

---

## 4. Token invalidation when FCM returns errors

| Check | Implementation |
|-------|----------------|
| After multicast | `response.failureCount > 0` → iterate `response.responses` (lines 219–230). |
| Per failure | `if (!resp.success)` → read `err?.code`. |
| Invalid / unregistered | `messaging/invalid-registration-token` or `messaging/registration-token-not-registered` → `deactivateToken(token).catch(() => {})`. |
| Deactivate | `UPDATE user_devices SET is_active = false WHERE fcm_token = $1`. |

**✔ Clean:** Invalid/unregistered tokens are deactivated; other errors are only logged.

---

## 5. No synchronous blocking calls

| Check | Implementation |
|-------|----------------|
| `sendNotification` | Uses `setImmediate(async () => { … })`; does not return a promise to the caller. |
| Callers | None `await` `pushService.sendNotification(...)`; all fire-and-forget. |
| Request path | No push work on the main request thread. |

**✔ Clean:** Push sending is offloaded; no blocking of HTTP request handling.

---

## 6. Throttling rules

| Rule | Implementation |
|------|----------------|
| Max 3 per user per minute | `shouldSendNotification`: count rows in `push_notification_log` with `user_id`, `user_type`, `created_at > oneMinuteAgo`; if `count >= MAX_PER_USER_PER_MINUTE` (3) return false (lines 69–76). |
| No duplicate type within 10s | Same function: exists row same `user_id`, `user_type`, `type`, `created_at > tenSecondsAgo` → return false (lines 78–84). |
| Constants | `MAX_PER_USER_PER_MINUTE = 3`, `MIN_SECONDS_SAME_TYPE = 10` (lines 53–55). |

**✔ Clean:** Throttling and duplicate-window behavior match requirements.

---

## 7. Deep link data in payload

| Check | Implementation |
|-------|----------------|
| Payload | `sendNotification(..., payload)` with `payload.data.deepLink`. |
| FCM message | `message.data.deepLink = (data.deepLink || '').toString()` (line 199). |
| Extra data | `jobId`, `applicationId`, etc. from `data` also added to `message.data` (lines 200–202). |
| Call sites | applicationService, ownerApplicationService, interviewService, interviewReminderService, notificationService all pass `data: { deepLink: '...', ... }`. |

**✔ Clean:** Deep link and related data are present in the push payload.

---

## 8. Firebase Admin initialization only once

| Check | Implementation |
|-------|----------------|
| Guard | `initFirebase()`: `if (firebaseInitialized) return;` and `if (admin.apps.length > 0) { firebaseInitialized = true; return; }` (lines 14–20). |
| Invocation | `initFirebase()` called once at module load (line 51). |
| No duplicate init | Credentials path only runs when `admin.apps.length === 0`. |

**✔ Clean:** Firebase Admin is initialized at most once per process.

---

## Summary

| # | Check | Result |
|---|--------|--------|
| 1 | No `sendPushNotification` usage | ✔ Clean |
| 2 | pushService used for all push | ✔ Clean |
| 3 | push_notification_log per push | ✔ Clean |
| 4 | Token invalidation on FCM errors | ✔ Clean |
| 5 | No synchronous blocking | ✔ Clean |
| 6 | Throttling (3/min, 10s same type) | ✔ Clean |
| 7 | Deep link in payload | ✔ Clean |
| 8 | Firebase init once | ✔ Clean |

---

## Result

**✔ Clean architecture** — No blocking issues or minor improvements required for the audited items.  
Push refactor is validated: single push path, logging, token handling, non-blocking behavior, throttling, deep link, and one-time Firebase init all match the intended design.
