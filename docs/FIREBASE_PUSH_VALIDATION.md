# Firebase Push Setup – Validation Audit

**Date:** 2025-02-12  
**Scope:** Flutter config, device registration, backend storage, deep links, test scenarios.

---

## 1. firebase_options.dart generated correctly

| Check | Status | Details |
|-------|--------|---------|
| File exists | ✅ | `lib/firebase_options.dart` present |
| Structure | ✅ | Class `DefaultFirebaseOptions`, getter `currentPlatform` returning `FirebaseOptions` |
| **Generated content** | ❌ | **Placeholder only** – getter throws `UnsupportedError` with message to run `flutterfire configure` |

**Verdict:** **Not generated.** The file is the placeholder. Run `flutterfire configure` from the project root to replace it with the real generated file (with platform-specific options). Until then, `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` will throw at startup.

---

## 2. google-services.json present

| Check | Status | Details |
|-------|--------|---------|
| File exists | ❌ | No `google-services.json` found in the project |

**Expected location:** `android/app/google-services.json` (created by `flutterfire configure`).

**Verdict:** **Missing.** Required for Android FCM. Run `flutterfire configure` and ensure Android is selected.

---

## 3. GoogleService-Info.plist present

| Check | Status | Details |
|-------|--------|---------|
| File exists | ❌ | No `GoogleService-Info.plist` found in the project |

**Expected location:** `ios/Runner/GoogleService-Info.plist` (created by `flutterfire configure`).

**Verdict:** **Missing.** Required for iOS FCM. Run `flutterfire configure` and ensure iOS is selected.

---

## 4. Firebase.initializeApp() called before runApp()

| Check | Status | Details |
|-------|--------|---------|
| In main() | ✅ | `lib/main.dart` line 41: `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);` |
| Before runApp | ✅ | Line 45: `runApp(const JobtreeApp());` – after Firebase init and `PushNotificationService().initialize()` |
| Options used | ✅ | Uses `DefaultFirebaseOptions.currentPlatform` (correct for FlutterFire) |

**Verdict:** **Correct.** Initialization order is correct; once `firebase_options.dart` is generated, this will work.

---

## 5. Device token registration works

| Check | Status | Details |
|-------|--------|---------|
| Flutter: get token | ✅ | `PushNotificationService.registerTokenIfLoggedIn()` uses `_messaging.requestPermission()` then `_messaging.getToken()` |
| Flutter: call API | ✅ | Calls `_api.registerFcmDevice(fcmToken: fcmToken, platform: platform)` with `platform`: `'ios'` \| `'android'` |
| API method | ✅ | `ApiService.registerFcmDevice()` POST to `/device/register` with `fcmToken`, `platform`, `requireAuth: true` |
| Backend route | ✅ | `POST /api/device/register` in `deviceRoutes.js`, validates body, calls `pushService.registerDevice(req.userId, req.userType, fcmToken, platform)` |
| When called | ✅ | From `main()` after init: `registerTokenIfLoggedIn()` in `PushNotificationService.initialize()`; and in both owner and seeker home `initState()` via `registerTokenIfLoggedIn()` |

**Verdict:** **Implemented.** End-to-end registration flow is correct. It only runs when the user is logged in (token present). If Firebase is not configured (placeholder options), `initialize()` will throw before registration runs.

---

## 6. Device token stored in backend user_devices table

| Check | Status | Details |
|-------|--------|---------|
| Table exists | ✅ | Migration `create_user_devices_table` in `backend/src/database/migrate.js`: `user_devices` with `user_id`, `user_type`, `fcm_token`, `platform`, `is_active`, timestamps |
| Indexes | ✅ | Unique index on `fcm_token` WHERE `is_active = true`; indexes on `(user_id, user_type)` and active devices |
| registerDevice() | ✅ | `pushService.registerDevice()`: deactivates any existing row for `fcm_token`, then `INSERT` into `user_devices` with `is_active = true` |
| Unregister | ✅ | `unregisterDevice` / `deactivateAllDevicesForUser` set `is_active = false` |

**Verdict:** **Implemented.** Tokens are persisted in `user_devices`; same token can be re-registered (old row deactivated, new row inserted).

---

## 7. Notification opens deep link

| Check | Status | Details |
|-------|--------|---------|
| Payload has deepLink | ✅ | Backend sends `data: { deepLink: 'app://owner/job/...' }` or `app://seeker/applications` (see pushService / notification triggers) |
| Flutter: parse | ✅ | `PushNotificationService`: `message.data['deepLink']` parsed via `PushDeepLink.parse()` (scheme, host, path) |
| Foreground | ✅ | `FirebaseMessaging.onMessage` → `_onForegroundMessage` (debugPrint; no navigation – tap not applicable in foreground) |
| Background tap | ✅ | `FirebaseMessaging.onMessageOpenedApp` → `_parseDeepLink` → `_deepLinkController.add(link)` |
| Terminated tap | ✅ | `getInitialMessage()` in `initialize()` → `_pendingDeepLink` set and added to stream; home screens call `getAndClearPendingDeepLink()` in `addPostFrameCallback` |
| Owner navigation | ✅ | `_JobOwnerHomeScreenState`: `_navigateFromDeepLink(link)` for `link.path.startsWith('job/')` → `CandidateListScreen(jobId)` |
| Seeker navigation | ✅ | `_SeekerHomeScreenState`: `_handleSeekerDeepLink(link)` for `applications` or `applications/` → `_selectedTab = 1` |

**Verdict:** **Implemented.** Deep link is in payload; background and terminated taps result in navigation to the correct screen (owner: job candidates; seeker: applications tab).

---

## Test scenarios (code path verification)

| Scenario | Code path | Status |
|----------|-----------|--------|
| **Foreground push** | App in foreground → `onMessage` → `_onForegroundMessage` → debugPrint. No system tray by default; message is received. Optional: add local notification for visibility. | ✅ Implemented (received; no UI beyond debug) |
| **Background push** | Push in tray → user taps → `onMessageOpenedApp` → deep link stream → owner/seeker home subscribes → `_navigateFromDeepLink` / `_handleSeekerDeepLink`. | ✅ Implemented |
| **Terminated push** | App killed → push in tray → user taps → app starts → `main()` → Firebase init → `PushNotificationService.initialize()` → `getInitialMessage()` → `_pendingDeepLink` set → home mounts → `addPostFrameCallback` → `getAndClearPendingDeepLink()` → navigate. | ✅ Implemented |

All three scenarios are supported in code. **Actual behavior** depends on: (1) real `firebase_options.dart`, (2) `google-services.json` and `GoogleService-Info.plist`, (3) backend FCM credentials, (4) device permission and network.

---

## Summary

| # | Item | Status |
|---|------|--------|
| 1 | firebase_options.dart generated correctly | ❌ Placeholder only |
| 2 | google-services.json present | ❌ Missing |
| 3 | GoogleService-Info.plist present | ❌ Missing |
| 4 | Firebase.initializeApp() before runApp() | ✅ |
| 5 | Device token registration works | ✅ (code path complete) |
| 6 | Token stored in user_devices | ✅ |
| 7 | Notification opens deep link | ✅ |

---

## Production readiness

**Conclusion: Not production ready until Firebase config is complete.**

- **Blockers**
  1. **firebase_options.dart** is still the placeholder. Run `flutterfire configure` and replace with the generated file.
  2. **google-services.json** and **GoogleService-Info.plist** are missing. They are created by `flutterfire configure`; add the plist to the iOS Runner target in Xcode if needed.
  3. Backend must have valid Firebase Admin credentials (`GOOGLE_APPLICATION_CREDENTIALS` or `FIREBASE_SERVICE_ACCOUNT_JSON`) and migrations run so `user_devices` (and push log) exist.

- **Once the above are done**
  - Initialization order, registration flow, `user_devices` storage, and deep link handling are in place.
  - Foreground, background, and terminated flows are implemented; manual testing with a real device and test-push is recommended before release.

**Recommended steps**

1. Run `flutterfire configure` (project root), select Firebase project and Android + iOS.
2. Confirm `lib/firebase_options.dart` is generated (no longer throws), `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` exist.
3. In Xcode: add **Push Notifications** (and **Background Modes → Remote notifications**), ensure `GoogleService-Info.plist` is in the Runner target.
4. Set backend env for Firebase Admin; run `npm run db:migrate` if not already done.
5. Test on a real device: login → Profile → “Send test push” → verify notification in foreground, background, and after cold start; verify tap opens the correct screen.
