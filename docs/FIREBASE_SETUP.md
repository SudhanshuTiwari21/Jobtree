# Firebase & FCM Setup (Jobtree)

This guide ensures FCM works on Android and iOS (foreground, background, and when the app is terminated).

---

## 1. Run FlutterFire Configure

From the **project root** (where `pubspec.yaml` lives):

```bash
flutterfire configure
```

- Sign in with Google if prompted.
- Select or create a Firebase project.
- Choose the platforms to configure (Android, iOS).
- The CLI will create/update the config files below.

---

## 2. Required Files After `flutterfire configure`

| File | Location | Purpose |
|------|----------|---------|
| `firebase_options.dart` | `lib/firebase_options.dart` | Generated; contains `DefaultFirebaseOptions.currentPlatform` for `Firebase.initializeApp()`. **Replaces** the placeholder that throws. |
| `google-services.json` | `android/app/google-services.json` | Android Firebase config (package name, API keys). |
| `GoogleService-Info.plist` | `ios/Runner/GoogleService-Info.plist` | iOS Firebase config (bundle ID, etc.). |

If any of these are missing after `flutterfire configure`, run it again and ensure Android/iOS are selected.

---

## 3. Flutter Code (Already Wired)

- **`main.dart`**  
  - Calls `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before `runApp()`.
  - Then calls `PushNotificationService().initialize()` (FCM listeners + token registration).

- **`lib/services/push_notification_service.dart`**  
  - Does **not** call `Firebase.initializeApp()` again; relies on `main()`.
  - Background handler uses `DefaultFirebaseOptions.currentPlatform` when initializing in the background isolate.

- **`lib/firebase_options.dart`**  
  - Before running `flutterfire configure`: placeholder that throws with instructions.
  - After `flutterfire configure`: generated file with real options; **keep it** and do not commit secrets if you use a private repo with env-specific config.

---

## 4. Android

- **Google Services plugin**  
  - In `android/settings.gradle.kts`: `id("com.google.gms.google-services") version "4.4.2" apply false`  
  - In `android/app/build.gradle.kts`: `id("com.google.gms.google-services")` applied.

- **minSdk**  
  - Set to **21** in `android/app/build.gradle.kts` (required for Firebase).

- **google-services.json**  
  - Must be at `android/app/google-services.json` (created by `flutterfire configure`).

---

## 5. iOS

- **Push capability & APNS**  
  - In Xcode: open `ios/Runner.xcworkspace` → select **Runner** target → **Signing & Capabilities** → **+ Capability** → add **Push Notifications** (and **Background Modes** if not already there).
  - The project already has `Runner/Runner.entitlements` with `aps-environment = development`. For release, use a distribution profile that has push enabled.

- **Background modes**  
  - **Remote notifications** is set in `ios/Runner/Info.plist` under `UIBackgroundModes` → `remote-notification`.

- **GoogleService-Info.plist**  
  - Must be in `ios/Runner/` (created by `flutterfire configure`). Add it to the Runner target in Xcode if it’s not auto-added.

---

## 6. Backend (FCM)

- Backend uses **Firebase Admin SDK** and **FCM** to send messages.
- Set in environment (e.g. `.env`):
  - `GOOGLE_APPLICATION_CREDENTIALS` = path to service account JSON, **or**
  - `FIREBASE_SERVICE_ACCOUNT_JSON` = base64 or raw JSON of the service account.
- Service account must have **Firebase Cloud Messaging** (or full Firebase Admin) permissions.

---

## 7. Test Push (Temporary)

1. **Run the app** (Android and/or iOS), **log in** as owner or seeker.
2. **Profile** → **Send test push** (owner: Profile tab; seeker: Profile tab in bottom nav).
3. Backend sends a test notification to the current user’s registered device(s).

**Verify in all three states:**

- **Foreground** – App open: you should see the notification (or in-app handling).
- **Background** – App in background: notification should appear in the system tray; tap opens app and deep link.
- **Terminated** – Force-close app, send test again: notification should appear; tap should launch app and open the correct screen.

If you don’t receive the test:
- Ensure the device has a valid FCM token (login triggers registration).
- Check backend logs for FCM errors (invalid token, wrong project, etc.).
- On iOS, ensure the app has notification permission and the capability/entitlements are set.

---

## 8. Summary Checklist

- [ ] Run `flutterfire configure` and get no errors.
- [ ] `lib/firebase_options.dart` exists and exposes `DefaultFirebaseOptions.currentPlatform` (no longer the placeholder).
- [ ] `android/app/google-services.json` exists.
- [ ] `ios/Runner/GoogleService-Info.plist` exists and is in the Runner target.
- [ ] Android: google-services plugin applied, minSdk 21.
- [ ] iOS: Push Notifications capability and `UIBackgroundModes` → `remote-notification` enabled.
- [ ] Backend: Firebase Admin credentials set; device registration and test-push work.
- [ ] Test push received in foreground, background, and after cold start.
