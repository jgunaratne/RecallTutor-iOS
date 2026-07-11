# Recall Tutor — App Store Submission Checklist

Pre-submission checklist (Recall Tutor hasn't been submitted yet). Several
items below exist specifically because **PodPal** (this developer's sibling
app, same account) was rejected on its first submission for IAP-not-submitted,
missing EULA/Privacy Policy links, and a broken subscription — see
`../podchat/APPSTORE_TODO.md` for the full story. Work through this top to
bottom before archiving.

---

## 1. Build hygiene

- [ ] Bump `CURRENT_PROJECT_VERSION` (currently `1`) if you've archived before,
      or leave at `1` for a genuinely first upload.
- [ ] `MARKETING_VERSION` is `1.0` — fine for a first release.
- [ ] **⚠️ Set the scheme's StoreKit Configuration back to `None`** before
      archiving for release (Product → Scheme → Edit Scheme → Run → Options).
      It's currently wired to `RecallTutor.storekit` for local testing — this
      exact setting is what let PodPal accidentally ship a build against the
      sandbox config once. A release build must fetch real products from App
      Store Connect, not the local `.storekit` file.
- [ ] Confirm `IPHONEOS_DEPLOYMENT_TARGET` (currently **26.0**) is
      intentional — this excludes every device that can't run iOS 26. If this
      was just Xcode's new-project default rather than a deliberate choice,
      consider lowering it to widen your addressable device pool.
- [ ] Run on a physical device (not just Simulator) once — App Check,
      Sign in with Apple, and StoreKit sandbox purchases all behave
      differently on-device.
- [ ] Archive and validate in Xcode Organizer before uploading (`Validate App`
      catches missing icons/entitlements/provisioning issues early).

## 2. Privacy & permissions

- [ ] `NSMicrophoneUsageDescription` is already set in Info.plist
      ("Recall Tutor uses the microphone so you can ask the voice tutor
      questions.") — no action needed.
- [ ] **No `PrivacyInfo.xcprivacy` manifest found** in the app target. Apple
      increasingly requires one for apps that call "required reason" APIs
      (this app uses `UserDefaults` directly, which is one). Third-party SDKs
      (Firebase, GoogleSignIn) ship their own manifests, but the app target
      itself doesn't have one yet. Check whether Xcode's App Store Connect
      upload step flags this — if so, add a minimal `PrivacyInfo.xcprivacy`
      declaring the `UserDefaults` reason.
- [x] `PaywallView` now links to Privacy Policy + Terms of Use
      (Guideline 3.1.2(c) — this is exactly what PodPal was rejected for).
- [ ] **Privacy Policy must be live at a real URL before submitting** — see
      §6 below for a ready-to-host draft, then update the URL in
      `PaywallView.legalLinks` if it differs from
      `https://gunaratne.com/recall-tutor/privacy`.

## 3. App Store Connect — create the app record

- [ ] **My Apps → + → New App**. Bundle ID `com.gunaratne.RecallTutor`
      (register it in Certificates, Identifiers & Profiles first if it isn't
      already there).
- [ ] Primary language, SKU, name reservation — see `APP_STORE_CONTENT.md`
      for the exact name/subtitle/category to enter.
- [ ] Age rating questionnaire — answer based on actual content (AI-generated
      educational text; no user-generated content shared between users, no
      mature content).

## 4. App Store Connect — Subscriptions (Monetization)

- [ ] Create subscription group (e.g. "Recall Tutor Pro").
- [ ] Product ID **`com.gunaratne.recalltutor.promonthly`** — must match
      `SubscriptionManager.swift` and `RecallTutor.storekit` exactly (already
      consistent in code; just don't typo it in App Store Connect).
- [ ] Duration: 1 Month. Price: $4.99, all countries (or your choice).
- [ ] Localization (en-US): Display Name `Recall Tutor Pro`, Description
      `Unlimited AI lectures, quizzes, illustrations, and voice tutoring.`
- [ ] **Review screenshot** — a screenshot of the paywall (`PaywallView`).
      Required; the subscription sits at "Missing Metadata" without one.
- [ ] Review notes for the subscription itself, e.g.: *"Recall Tutor Pro
      unlocks unlimited AI lectures, quizzes, and voice tutoring on the
      built-in tier. Test by generating 3 lectures to trigger the paywall,
      then subscribe in sandbox."*
- [ ] 1024×1024 promotional image (optional but recommended).
- [ ] **⚠️ Submit the subscription in the SAME submission as the app
      build** — "Add for Review" only adds the app version by default. You
      must explicitly add the subscription so the submission shows **2
      items**. This exact mistake (submitting the app alone) is what
      reproduced PodPal's Guideline 2.1(b) rejection — don't repeat it.

## 5. App Store Connect — App Information

- [ ] **EULA**: App Information → License Agreement → select
      **Standard Apple EULA**.
- [ ] **Privacy Policy URL**: set to the URL you host from §6 below.
- [ ] Category: Education (primary) / Reference (secondary) — see
      `APP_STORE_CONTENT.md`.
- [ ] Support URL — you don't have one yet; either stand up a minimal page
      or reuse an existing domain (see `APP_STORE_CONTENT.md`'s TODO).

## 6. Privacy Policy — draft to host

Apple requires a **live, functional URL** before submission, and the paywall
should link to it (confirm `PaywallView` already includes a Privacy Policy /
Terms of Use link — if not, add one before archiving). Host this at e.g.
`https://gunaratne.com/recall-tutor/privacy`:

```
Privacy Policy — Recall Tutor
Last updated: [date]

Recall Tutor ("the app") is developed by Junius Gunaratne.

INFORMATION WE COLLECT
- Account info (if you sign in): email address and display name, via Sign in
  with Apple or Google (Firebase Authentication).
- Usage data (if signed in): number of free lectures used and subscription
  status, stored in Cloud Firestore, scoped to your account only.
- API keys (optional): if you supply your own Anthropic or Gemini API key,
  it is stored only in your device's Keychain and is never sent to our
  servers — it goes directly from your device to that provider's API.
- Microphone audio: used only when you tap to ask the voice tutor a
  question, streamed live to Google's Gemini API for a spoken response. Audio
  is not stored by us.
- Lecture content you request (topics/questions) is sent to the AI provider
  (Anthropic or Google Gemini, depending on your settings) to generate a
  response. We do not sell this data or use it for advertising.

HOW WE USE INFORMATION
Solely to provide the app's features: generating lectures/quizzes/voice
tutoring, tracking free-tier usage, and managing your subscription.

THIRD-PARTY SERVICES
- Google Firebase (Authentication, Cloud Firestore, Firebase AI) — see
  https://firebase.google.com/support/privacy
- Anthropic API (if you supply your own key) — see
  https://www.anthropic.com/legal/privacy
- Google Gemini API (if you supply your own key, or via the built-in tier) —
  see https://policies.google.com/privacy
- Apple (Sign in with Apple, StoreKit) — see
  https://www.apple.com/legal/privacy/

DATA RETENTION & DELETION
Signed-in users' account data can be deleted on request by contacting
[your email]. Deleting your account removes your Firestore profile,
usage record, and subscription status.

CHILDREN'S PRIVACY
Recall Tutor is not directed at children under 13 and does not knowingly
collect personal information from children under 13.

CHANGES
We may update this policy; the "Last updated" date above will reflect the
most recent revision.

CONTACT
[your email]
```

Adjust the bracketed placeholders before publishing. This is a starting draft,
not legal advice — have someone review it if you want stronger assurances.

## 7. App Store Connect — Business

- [ ] Confirm the **Paid Applications Agreement** is still Active for this
      account (it should already be, from PodPal — agreements are
      account-wide, not per-app — but double check under
      Business → Agreements, Tax, and Banking).
- [ ] Tax and banking info complete (should already be done from PodPal).

## 8. Screenshots

- [ ] Capture screenshots for each required device size (6.9" and 6.5"
      iPhone at minimum; iPad if you support it — check
      `TARGETED_DEVICE_FAMILY`, currently `"1,2"` meaning iPhone **and**
      iPad, so iPad screenshots are required too).
- [ ] Use the text overlay suggestions in `APP_STORE_CONTENT.md`.
- [ ] Include one screenshot of the paywall — doubles as the subscription's
      required review screenshot (§4).

## 9. App Review Information

- [ ] Paste the listing content, review notes, and sign-in guidance from
      `APP_STORE_CONTENT.md` into the corresponding App Store Connect fields.
- [ ] Fill in your real contact phone number in the Contact Information
      section (left as a placeholder in `APP_STORE_CONTENT.md`).

## 10. Final submission

- [ ] Archive with StoreKit Configuration set to **None** (§1).
- [ ] Upload via Xcode Organizer or Transporter.
- [ ] In App Store Connect, attach the build to the version, then **add the
      Recall Tutor Pro subscription to the same submission** (§4) — verify
      the submission shows **2 items** before clicking Submit.
- [ ] Submit for review.
- [ ] After submission, watch for a Resolution Center message — reply
      promptly if Apple has questions (PodPal's turnaround was fast once the
      actual issues were addressed).
