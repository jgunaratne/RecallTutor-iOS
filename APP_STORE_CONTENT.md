# Recall Tutor — App Store Listing Content

Copy-paste guide for every field in App Store Connect.

---

## App Name
Recall Tutor — AI Study Coach

## Subtitle (30 chars max)
AI Lectures, Quizzes & Voice

## Category
Primary: Education
Secondary: Reference

---

## Promotional Text (170 chars max — can be updated without review)

```
Pick any topic and get a bite-sized AI lecture with visual cards, a recall quiz, and a live voice tutor who explains it out loud — at your reading level.
```

## Description (4,000 chars max)

```
Recall Tutor turns any topic into a lecture you'll actually remember.

Pick a subject — Science, Humanities, Social Science, Business & Finance, Jobs & Careers — or type your own question, and get a bite-sized AI lecture broken into clear visual cards, written at the reading level you choose: Elementary, Middle School, High School, or University.

VOICE TUTOR
Turn on the voice tutor for a real conversation about the lecture. It reads each card aloud as you flip through, answers spoken follow-up questions, and adapts on the fly — like having a professor next to you. Works out of the box with a Recall Tutor Pro subscription — no API key needed.

AI ILLUSTRATIONS
Dense cards get a generated illustration to break up the text and reinforce the concept — clean, conceptual, no clutter.

TEST YOUR RECALL
After each lecture, take a quiz built from what you just learned. Questions target real understanding, not rote memorization or verbatim phrasing — with a streak timer and a scorecard at the end.

ADAPTIVE READING LEVEL
The same topic, explained differently for a curious kid, a high schooler, or a university student. Switch levels any time in Settings.

FREE TO START
Generate your first 3 lectures on the built-in tutor at no cost — no API key required, just sign in. After that, subscribe to Recall Tutor Pro for unlimited lectures, quizzes, illustrations, and voice tutoring, or bring your own Anthropic or Gemini API key for unlimited use at no subscription cost.

RECALL TUTOR PRO — $4.99/MONTH
• Unlimited AI lectures on any topic
• Unlimited quizzes and voice tutor sessions
• AI-generated card illustrations
• Auto-renews monthly. Cancel anytime.

Privacy Policy: https://gunaratne.com/recall-tutor/privacy
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Keywords (100 chars max)

```
study,tutor,ai,learn,flashcards,quiz,education,lecture,voice,recall,homework,school
```

---

## What's New — Version 1.0

```
🎉 Welcome to Recall Tutor!

• Pick a topic or ask your own question — get an AI lecture with visual cards
• Choose your reading level: Elementary, Middle School, High School, or University
• Voice tutor reads lectures aloud and answers spoken questions in real time
• AI-generated illustrations for dense cards
• Quiz mode tests real understanding, not memorization
• Sign in with Apple or Google to unlock 3 free lectures, no API key needed
• Bring your own Anthropic or Gemini API key for unlimited use
• First-launch walkthrough gets you started in seconds
```

---

## Support URL

```
TODO — e.g. https://gunaratne.com/recall-tutor/support
```

## Marketing URL

*(Leave blank, or use your website if you have one)*

## Version

```
1.0
```

## Copyright

```
© 2026 Junius Gunaratne
```

---

## App Review Information

### Sign-In Information

Sign-in is **optional** — the app is fully usable without an account by
supplying a personal Anthropic or Gemini API key in Settings. Signing in with
Apple or Google only unlocks the built-in (no-key) tier, which is metered (3
free lectures, then Recall Tutor Pro).

Given that, either:
- Leave "sign-in required" **unchecked**, since the app doesn't require an
  account to function, **or**
- Check it and provide a demo account/note if you'd rather reviewers see the
  built-in tier and paywall without needing their own API key:

> **Notes (paste below):** "Sign-in is optional. Reviewers can either (a) add
> a personal Gemini API key in Settings → Gemini API key to use the app with
> no account at all, or (b) sign in with Apple/Google to test the built-in
> tier (3 free lectures, then the Recall Tutor Pro paywall). No existing
> credentials are needed — Sign in with Apple lets reviewers create an
> account on the spot."

### Contact Information

```
First name: Junius
Last name:  Gunaratne
Phone:      (your phone number)
Email:      jgunaratne@gmail.com
```

### App Review Notes (4,000 chars max)

```
Recall Tutor generates original AI-written lectures, illustrations, and quizzes from a topic or question the user provides — it does not aggregate, stream, or provide access to any third-party copyrighted media, catalog, or discovery service.

Recall Tutor offers a free tier (3 distinct AI-generated lectures on the built-in tutor). After that, users may subscribe to Recall Tutor Pro ($4.99/month, auto-renewable) for unlimited lectures, quizzes, illustrations, and voice tutoring — powered by Google Gemini via Firebase — or supply their own Anthropic or Gemini API key at no charge, with no limit. Cancellation is available in-app via the system Manage Subscription sheet.

Technical details for review:

• SUBSCRIPTION: Recall Tutor Pro is a $4.99/month auto-renewable subscription. The paywall discloses the price, renewal terms, and links to Privacy Policy and Terms of Use per guideline 3.1.2. Users can manage/cancel via the native Manage Subscription sheet in Settings.

• AI LECTURES/QUIZZES: Powered by Gemini via the Firebase AI Logic SDK for signed-in users on the built-in tier (no API key required — Firebase handles auth), or directly via a user-supplied Anthropic or Gemini API key stored in the device Keychain.

• VOICE TUTOR: Uses Gemini Live for real-time voice conversation about the lecture. With a user-provided Gemini API key it connects via raw WebSocket (gemini-3.1-flash-live-preview); for signed-in users without a key it uses the Firebase AI SDK (gemini-2.5-flash-native-audio). Microphone access is requested only when the user taps to ask a question.

• AI ILLUSTRATIONS: Card illustrations are generated the same dual-backend way (Gemini image models via a personal key, or Firebase AI for signed-in users).

• ACCOUNT: Optional. Users can sign in with Apple or Google (Firebase Auth), or use the app fully with their own API key and no account at all. Sign-in is only required to use the built-in (no-key) tier. Signed-in profile data (email, display name, subscription status, free-lecture usage) is stored in Cloud Firestore, scoped to that user's own document.

• NO THIRD-PARTY CONTENT: Recall Tutor does not access, stream, or redistribute any copyrighted or proprietary third-party content. All lecture, quiz, and illustration content is generated fresh by the AI model in response to the user's topic.

To test: add a personal Gemini API key in Settings for unlimited use with no account, or sign in with Apple/Google to reach the paywall after 3 free lectures.
```

---

## Screenshots Text Overlays

Use these as text overlays on your App Store screenshots:

1. **"Pick any topic, get a lecture"** — Show the home screen with topic categories
2. **"Bite-sized cards, your reading level"** — Show a lecture card with an AI illustration
3. **"Talk it through with a voice tutor"** — Show the voice tutor controls mid-lecture
4. **"Test what you just learned"** — Show the quiz view with a question
5. **"See how you did"** — Show the scorecard
6. **"Free to start, no API key needed"** — Show the sign-in / paywall screen

---

## App Store Version Release

Recommended: **Manually release this version** — so you can verify everything
looks right in the store listing before it goes live.
