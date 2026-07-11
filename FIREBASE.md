# Firebase — Built-in Tutor Setup

Recall Tutor supports a **built-in (managed) Gemini tier** so users without an
API key can still generate lectures: they sign in with Google (Firebase Auth)
and lectures run through **Firebase AI**. Because that usage costs *us* money,
it is metered — **3 free lectures**, then the **Recall Tutor Pro** paywall
appears. Users who add their own Anthropic or Gemini API key in Settings are
never metered.

The code is fully wired (ported from ../podchat). Until you complete the tasks
below, the app builds and runs in **bring-your-own-key mode only** — Firebase
is simply never configured and all account/subscription UI stays hidden.

---

## Your task checklist

- [ ] **1. Register the app in Firebase.**
  - [Firebase console](https://console.firebase.google.com) → your project
    (you can reuse the podchat project) → **Add app → iOS**.
  - Bundle ID: `com.gunaratne.RecallTutor`.
  - Download **`GoogleService-Info.plist`** and drop it into the
    **`RecallTutor/`** source folder (next to `RecallTutorApp.swift`). The
    folder is a synchronized group, so Xcode picks it up automatically. It is
    gitignored.

- [ ] **2. Enable Google sign-in.**
  - Console → **Build → Authentication → Sign-in method → Google → Enable**.

- [ ] **3. Set the URL scheme.**
  - Open the root **`Info.plist`** and replace both `REVERSED_CLIENT_ID`
    placeholder strings with the `REVERSED_CLIENT_ID` value from your
    `GoogleService-Info.plist` (looks like
    `com.googleusercontent.apps.1234567890-abcdef`).

- [ ] **4. Enable Firebase AI (Gemini Developer API).**
  - Console → **Build → AI Logic** → set up the **Gemini Developer API**
    backend (the code uses `FirebaseAI.firebaseAI(backend: .googleAI())`).

- [ ] **5. Enable Cloud Firestore (user database).**
  - Console → **Build → Firestore Database → Create database** (production
    mode). Signed-in users are stored in the **`recall-tutor-users`**
    collection (one doc per Firebase UID: profile, `isPro` subscription flag,
    free-lecture usage).
  - Set the security rules so each user can only touch their own doc:

    ```
    rules_version = '2';
    service cloud.firestore {
      match /databases/{database}/documents {
        match /recall-tutor-users/{uid} {
          allow read, write: if request.auth != null && request.auth.uid == uid;
        }
      }
    }
    ```

  - To comp a user Pro access manually, set `isPro: true` on their doc in the
    console — the app honors the server-side grant on next launch/sign-in.

- [ ] **6. Local subscription testing.**
  - A ready-to-use StoreKit configuration is at **`RecallTutor.storekit`**
    (product `com.gunaratne.recalltutor.promonthly`, $4.99/month).
  - Xcode: **Product → Scheme → Edit Scheme → Run → Options → StoreKit
    Configuration** → select `RecallTutor.storekit`.
  - Now you can hit the paywall, subscribe, and restore in the Simulator.
    DEBUG builds also get a **Pro Override** toggle and a **Reset Free
    Lecture Count** button in Settings → Subscription.
  - Set the configuration back to **None** before archiving for release.

- [ ] **7. (For shipping) Create the subscription in App Store Connect.**
  - Product ID **`com.gunaratne.recalltutor.promonthly`** (must match
    `SubscriptionManager.swift` and `RecallTutor.storekit` exactly),
    auto-renewable, 1 month.
  - See ../podchat/SUBSCRIPTION.md for the full App Store Connect walkthrough,
    including the "first subscription must be submitted together with an app
    version" trap.

---

## How it works in the app

| Concern | File |
| --- | --- |
| Google sign-in / auth state | `RecallTutor/Services/AuthManager.swift` |
| Free-tier metering + StoreKit 2 purchase/restore | `RecallTutor/Services/SubscriptionManager.swift` |
| Firestore user docs (`recall-tutor-users/{uid}`) | `RecallTutor/Services/UserStatsService.swift` |
| Managed Gemini generation (lectures, quiz, reactions) | `RecallTutor/Services/FirebaseAIClient.swift` |
| Provider routing (`.anthropic` / `.gemini` / `.firebase`) | `RecallTutor/Services/GeminiClient.swift` (`AIService`) |
| Metering gate on new lectures | `RecallTutor/Services/ChatModel.swift` (`runExchange`) |
| Sign-in prompt | `RecallTutor/Views/SignInSheet.swift` |
| Paywall | `RecallTutor/Views/PaywallView.swift` |
| Account + Subscription sections | `RecallTutor/Views/SettingsView.swift` |

Rules of the meter (mirrors podchat):

- The limit counts **distinct lectures** (conversations), not requests —
  follow-ups, quizzes, and reactions on an already-counted lecture are free.
- The free limit is one constant: `SubscriptionManager.freeLectureLimit` (3).
- Pro subscribers and personal-API-key users are never metered.
- Usage is stored per-Firebase-UID in UserDefaults **and** mirrored to the
  user's `recall-tutor-users` Firestore doc, so a reinstall or device change
  can't reset the count (local ∪ server union on sign-in, like podchat).
- The subscription status (`isPro`) is pushed to Firestore after every
  StoreKit check, and a server-side `isPro: true` (set manually in the
  console) grants Pro in the app.
- The voice tutor (Gemini Live) and card illustrations work on the built-in
  tier too: voice via the Firebase AI Live API, images via
  `gemini-2.5-flash-image` on the same googleAI backend — no key needed.
