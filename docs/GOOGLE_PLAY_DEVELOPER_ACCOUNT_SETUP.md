# Google Play Developer Account – Step-by-Step Setup

One-time **$25 USD** registration. Use this account to publish or run internal/closed testing for your Android app (e.g. JobTree).

---

## 1. Prerequisites

- **Google Account** (Gmail) with **2-step verification** turned on.
- **Payment method**: Credit or debit card (Visa, Mastercard, Amex, Discover). Prepaid cards are **not** accepted.
- **Age**: You must be at least **18** to register.
- **Identity**: Government-issued ID may be required for verification (especially for organization accounts).

---

## 2. Register for a developer account

1. Go to **[play.google.com/console](https://play.google.com/console)** and sign in with your Google Account.

2. **Accept the Developer Distribution Agreement**  
   Read and accept Google’s terms.

3. **Pay the registration fee**  
   - One-time **$25 USD** (non-refundable).  
   - Enter card details when prompted.  
   - Complete the payment.

4. **Choose account type**  
   - **Individual** – personal developer (name will be shown on the store).  
   - **Organization / Company** – business name; may require D-U-N-S and extra verification.  
   - **Educational / Government / Non-profit** – if it applies.  
   You **cannot change** this later, so choose carefully.

5. **Fill in developer profile**  
   - Developer name (shown on Play Store).  
   - Email and phone.  
   - For organization: legal name, address, contact, and any required verification (e.g. D-U-N-S, website).

6. **Complete identity / organization verification**  
   If Google asks for it:
   - **Individual**: Government ID (e.g. passport, driver’s license).  
   - **Organization**: Follow the prompts (e.g. document upload, website, D-U-N-S).  
   Verification can take from a few hours to a few days.

7. **Finish registration**  
   Once payment and any verification are done, you’ll land in the **Play Console** dashboard.

---

## 3. Create your app in Play Console

1. In Play Console, click **“Create app”** (or “Add app” / “Create application”).

2. **App details**  
   - **App name**: e.g. `JobTree`  
   - **Default language**: e.g. English (United States)  
   - **App or game**: App  
   - **Free or paid**: Free (or Paid if you plan to charge)

3. **Declarations**  
   - Confirm compliance with **Developer Program Policies** and **US export laws** (check the boxes).

4. Click **“Create app”**.  
   Your app is created; you’ll be taken to its dashboard (e.g. **Dashboard** → **Release** → **Setup**).

---

## 4. Link your app’s package name (bundle ID)

Your Flutter app uses:

- **Application ID (package name):** `com.jobtree.jobtree`

You **don’t** need to “register” this separately; you’ll use it when you upload the first build.

1. In the left menu go to **Setup** → **App integrity** (or **App signing** / **Release** → **Setup**).
2. When you upload your first **AAB** (Android App Bundle), Play Console will associate it with this app and its package name.  
   So just build with:
   ```bash
   flutter build appbundle --release
   ```
   The built `.aab` will have the application ID from `android/app/build.gradle.kts` (`com.jobtree.jobtree`).

---

## 5. Complete required setup (before first release)

Play Console will show a **checklist**. Typical items:

| Task | Where | What to do |
|------|--------|------------|
| **App signing** | Setup → App integrity | Enroll in Play App Signing (recommended); use the key they provide or upload your own. |
| **Privacy policy** | Policy → App content | Add a URL to your app’s privacy policy (required if you collect data). |
| **App access** | Policy → App content | If the app is restricted (e.g. login-only), describe how testers/reviewers can get access. |
| **Ads** | Policy → App content | Declare if the app uses ads (e.g. “No” if you don’t). |
| **Content rating** | Policy → App content | Fill the questionnaire and get a rating (e.g. Everyone, Teen). |
| **Target audience** | Policy → App content | Set age groups and target countries. |
| **News app** | Policy → App content | Declare if it’s a news app (usually “No”). |
| **COVID-19** | Policy → App content | Declare if relevant (usually “No”). |
| **Data safety** | Policy → App content | Declare what data you collect and how it’s used. |

Work through each item until the checklist allows you to publish or send to test tracks.

---

## 6. Upload a build (internal testing)

1. In the left menu go to **Release** → **Testing** → **Internal testing** (or **Release** → **Internal testing**).

2. **Create new release**  
   - If asked, create a new **release** and choose the track **Internal testing**.

3. **Upload the AAB**  
   - Build: `flutter build appbundle --release`  
   - Path: `build/app/outputs/bundle/release/app-release.aab`  
   - Drag and drop the file or use “Upload” in the release screen.

4. **Release name**  
   - e.g. “1.0.0 (1)” or “Internal test 1”.

5. **Release notes**  
   - Short notes for testers (e.g. “First internal build”).

6. **Review and roll out**  
   - Save, then **Review release** → **Start rollout to Internal testing**.

7. **Add testers**  
   - Open the **Testers** tab for Internal testing.  
   - Create a **mailing list** (e.g. “Internal testers”) and add email addresses.  
   - Testers get a link to opt in and install the app from Play Console.

---

## 7. Summary checklist

- [ ] Google Account with 2-step verification  
- [ ] Pay $25 at [play.google.com/console](https://play.google.com/console)  
- [ ] Complete identity/org verification if asked  
- [ ] Create app in Play Console (name, language, free/paid, declarations)  
- [ ] Complete Setup & Policy (signing, privacy, content rating, data safety, etc.)  
- [ ] Build AAB: `flutter build appbundle --release`  
- [ ] Upload to **Internal testing** and add testers  

---

## Useful links

- **Play Console**: [play.google.com/console](https://play.google.com/console)  
- **Help – Create account**: [support.google.com/googleplay/android-developer/answer/6112435](https://support.google.com/googleplay/android-developer/answer/6112435)  
- **Registration fee & requirements**: [support.google.com/googleplay/android-developer/answer/10788890](https://support.google.com/googleplay/android-developer/answer/10788890)  

Your app’s **application ID** is `com.jobtree.jobtree` (from `android/app/build.gradle.kts`). Use it as-is when uploading the first AAB; no extra “registration” of the package name is needed beyond creating the app in Play Console.
