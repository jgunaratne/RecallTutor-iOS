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

- [ ] **5. Local subscription testing.**
  - A ready-to-use StoreKit configuration is at **`RecallTutor.storekit`**
    (product `com.gunaratne.recalltutor.promonthly`, $4.99/month).
  - Xcode: **Product → Scheme → Edit Scheme → Run → Options → StoreKit
    Configuration** → select `RecallTutor.storekit`.
  - Now you can hit the paywall, subscribe, and restore in the Simulator.
    DEBUG builds also get a **Pro Override** toggle and a **Reset Free
    Lecture Count** button in Settings → Subscription.
  - Set the configuration back to **None** before archiving for release.

- [ ] **6. (For shipping) Create the subscription in App Store Connect.**
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
- Usage is stored per-Firebase-UID in UserDefaults, so accounts on the same
  device don't share the allowance. (Unlike podchat there is no Firestore
  sync yet — a reinstall resets the local count.)
- The voice tutor (Gemini Live) and card illustrations still require a
  personal Gemini API key; the built-in tier covers lectures, quizzes, and
  reactions.
