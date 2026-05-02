# Testing Without Google / Apple Developer Accounts

**Short answer:** You **cannot** use **TestFlight** (iOS) or **Google Play beta** without paid developer accounts. You can still build and test in other ways.

---

## What requires paid accounts

| Goal | Apple | Google |
|------|--------|--------|
| **TestFlight** (iOS beta) | ✅ **Requires** [Apple Developer Program](https://developer.apple.com/programs/) ($99/year) | N/A |
| **Play Store internal/closed testing** | N/A | ✅ **Requires** [Google Play Console](https://play.google.com/console) ($25 one-time) |
| **Publish to stores** | Same Apple account | Same Google account |

There is no way to use TestFlight without an Apple Developer account, or Play Console beta without a Google Developer account.

---

## What you can do without paid accounts

### Android (no Google Developer account)

You can build and share an **APK** so testers install it directly (no Play Store).

1. **Build release APK**
   ```bash
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`

2. **Share the file**
   - Upload to Google Drive, Dropbox, or your own server and share the link.
   - Or send the file via email / USB.

3. **Tester installs**
   - On the Android device: enable **Install from unknown sources** (or “Install unknown apps” for the browser/file app).
   - Download the APK and open it to install.

**Optional:** [Firebase App Distribution](https://firebase.google.com/docs/app-distribution) lets you upload the same APK and invite testers by email; they get a link to download and install. No Play Developer account needed for Android.

---

### iOS (no Apple Developer account)

Options are limited because Apple only allows proper device installs via the Developer Program or enterprise.

1. **Run on the iOS Simulator (Mac only)**  
   No account needed. Good for UI and flow testing.
   ```bash
   flutter run
   ```
   Choose the iOS simulator when prompted.

2. **Run on your own iPhone (free provisioning)**  
   With a free Apple ID you can install the app on **your own** device via Xcode:
   - Open `ios/Runner.xcworkspace` in Xcode.
   - Select the Runner target → **Signing & Capabilities**.
   - Set **Team** to your Apple ID (Xcode can add it for free).
   - Connect your iPhone, select it as the run destination, and run.

   **Limitations:**  
   - App may need to be reinstalled every ~7 days.  
   - Only for devices you add in Xcode; not for sending to other people’s iPhones.  
   - No TestFlight, no App Store, no push notifications (push needs a paid account for proper provisioning).

3. **Sending to other iOS testers**  
   Without an Apple Developer account there is **no** supported way to put your app on someone else’s iPhone (no TestFlight, no ad‑hoc to strangers). They would need to use a simulator on a Mac or you need the $99/year program.

---

## Summary

| Scenario | Possible without paid account? |
|----------|--------------------------------|
| TestFlight (iOS) | ❌ No — needs Apple Developer ($99/year) |
| Play internal/closed testing (Android) | ❌ No — needs Google Play Developer ($25) |
| Share **Android APK** for direct install | ✅ Yes |
| Firebase App Distribution (Android APK) | ✅ Yes |
| Run on **iOS Simulator** | ✅ Yes |
| Run on **your own iPhone** (free provisioning) | ✅ Yes (with limits) |
| Send build to **other people’s iPhones** | ❌ No — need Apple Developer |

So: you **can** generate and use a **TestFlight-style workflow** only after you have the **Apple Developer Program**. Without it, you can still build an **Android APK** and share it for testing, and run the app on the **iOS Simulator** or **your own iPhone** with free provisioning.
