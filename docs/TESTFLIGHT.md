# TestFlight Build Guide (Jobtree iOS)

Use this to build and upload the Jobtree iOS app to TestFlight for beta testing.

## Prerequisites

1. **Apple Developer Program**  
   Enroll at [developer.apple.com](https://developer.apple.com) (paid).

2. **App in App Store Connect**  
   - Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**.  
   - Choose **iOS**, set **Bundle ID** to match your Xcode project (e.g. `com.yourcompany.jobtree`).  
   - Fill name, SKU, and primary language.

3. **Mac with Xcode**  
   Install Xcode from the Mac App Store and run it once to accept the license.

4. **Flutter**  
   From project root: `flutter doctor` and fix any issues (especially for iOS).

## One-time setup in Xcode

1. Open the iOS project:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Select the **Runner** project in the left sidebar, then the **Runner** target.
3. **Signing & Capabilities** tab:
   - Check **Automatically manage signing**.
   - Choose your **Team** (Apple Developer account).
   - Set **Bundle Identifier** to the same one you used in App Store Connect (e.g. `com.yourcompany.jobtree`).
4. If you use push notifications (FCM), ensure the **Push Notifications** capability is added (Xcode may add it when you enable it in the Apple Developer portal for this App ID).

## Build for TestFlight

From the project root:

```bash
# Default version from pubspec.yaml (e.g. 1.0.0+1)
./scripts/build_testflight.sh

# Or specify version and build number
./scripts/build_testflight.sh 1.0.0 2
```

Or run Flutter directly:

```bash
flutter build ipa
```

The IPA is generated at: **`build/ios/ipa/jobtree.ipa`**.

## Upload to App Store Connect

### Option A: Xcode Organizer (recommended)

1. In Xcode: **Window → Organizer**.
2. Open the **Archives** tab.
3. If your build doesn’t appear, use **Distribute App** from the **Product** menu with the **Runner** scheme and **Archive**.
4. Select the latest archive → **Distribute App** → **App Store Connect** → **Upload**.
5. Follow the prompts (signing, options). After upload, wait for processing in App Store Connect.

### Option B: Transporter app

1. Install [Transporter](https://apps.apple.com/app/transporter/id1450874784) from the Mac App Store.
2. Sign in with your Apple ID.
3. Drag `build/ios/ipa/jobtree.ipa` into Transporter and deliver.

### Option C: Command line

1. Create an [app-specific password](https://appleid.apple.com) for your Apple ID.
2. Run:
   ```bash
   xcrun altool --upload-app -f build/ios/ipa/jobtree.ipa -t ios -u YOUR_APPLE_ID -p YOUR_APP_SPECIFIC_PASSWORD
   ```

## After upload

1. In **App Store Connect** → your app → **TestFlight**.
2. Wait until the build status is **Ready to submit** (processing can take 5–30 minutes).
3. Add **Internal** or **External** testers and send the build for testing.
4. Testers install **TestFlight** from the App Store and open the invite to install your build.

## Troubleshooting

- **Signing errors**  
  In Xcode, confirm Team and Bundle ID, and that the App ID exists in the Apple Developer portal.

- **“No valid signing identity”**  
  In Keychain Access, ensure you have the **Apple Distribution** certificate. Xcode → **Preferences → Accounts** → select account → **Manage Certificates** and create/install distribution certificate if needed.

- **Firebase / Push**  
  For FCM to work on TestFlight builds, ensure:
  - `GoogleService-Info.plist` is in `ios/Runner/` (from `flutterfire configure`).
  - Push capability is enabled for the App ID and the app is signed with a provisioning profile that includes push.

- **Build number**  
  Each TestFlight upload needs a **new build number** (the `+N` in `1.0.0+N`). Use a higher number for each upload (e.g. `./scripts/build_testflight.sh 1.0.0 3`).
