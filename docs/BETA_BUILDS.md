# Beta Builds: iOS (TestFlight) & Android (Play / APK)

Use this to build and ship beta versions of Jobtree for testers on **iOS** and **Android**.

---

## Bundle IDs

| Platform | Bundle / Application ID |
|----------|--------------------------|
| iOS      | `com.jobtree.jobtree`    |
| Android  | `com.jobtree.jobtree`    |

Use these when creating the app in App Store Connect and Google Play Console.

---

## 1. iOS – TestFlight

### Prerequisites

- **Mac** with Xcode and Flutter.
- **Apple Developer Program** (paid).
- App created in [App Store Connect](https://appstoreconnect.apple.com) with Bundle ID `com.jobtree.jobtree`.
- In Xcode: open `ios/Runner.xcworkspace` → Runner target → **Signing & Capabilities** (Team, Bundle ID, Push if needed).

### Build

From project root:

```bash
./scripts/build_testflight.sh
# Or with version: ./scripts/build_testflight.sh 1.0.0 2
```

IPA path: **`build/ios/ipa/jobtree.ipa`**

### Upload to TestFlight

- **Xcode:** Window → Organizer → Archives → select build → Distribute App → App Store Connect → Upload.
- **Transporter:** Drag `build/ios/ipa/jobtree.ipa` into the app and deliver.
- **CLI:** `xcrun altool --upload-app -f build/ios/ipa/jobtree.ipa -t ios -u YOUR_APPLE_ID -p YOUR_APP_SPECIFIC_PASSWORD`

Then in App Store Connect → your app → **TestFlight** → add internal/external testers.

---

## 2. Android – Play internal testing (or APK)

### Prerequisites

- Flutter installed; Android SDK and signing keystore set up.
- App created in [Google Play Console](https://play.google.com/console) with application ID `com.jobtree.jobtree` (or create it on first upload).

### Build (AAB for Play Store)

From project root:

```bash
./scripts/build_android_release.sh
# Or with version: ./scripts/build_android_release.sh 1.0.0 2
```

AAB path: **`build/app/outputs/bundle/release/app-release.aab`**

### Upload for internal testers

1. Play Console → your app → **Testing** → **Internal testing**.
2. **Create new release** → Upload `app-release.aab`.
3. Add release notes → Save → Review release → Start rollout.
4. Add testers by email in the **Testers** tab.

### Optional: APK for direct install (e.g. Firebase App Distribution)

```bash
flutter build apk --release
```

APK path: **`build/app/outputs/flutter-apk/app-release.apk`**

Upload this to [Firebase App Distribution](https://console.firebase.google.com) or share the file for sideload testing.

---

## Quick reference

| Goal              | Command                          | Output path                                      |
|-------------------|----------------------------------|--------------------------------------------------|
| iOS TestFlight    | `./scripts/build_testflight.sh`  | `build/ios/ipa/jobtree.ipa`                     |
| Android Play beta | `./scripts/build_android_release.sh` | `build/app/outputs/bundle/release/app-release.aab` |
| Android APK       | `flutter build apk --release`    | `build/app/outputs/flutter-apk/app-release.apk` |

For more iOS detail (signing, Transporter, troubleshooting), see [TESTFLIGHT.md](./TESTFLIGHT.md).
