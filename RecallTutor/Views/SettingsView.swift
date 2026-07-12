import SwiftUI

/// Settings sheet: account (Google sign-in for the built-in tutor),
/// subscription, provider API keys (Keychain-backed), AI provider choice,
/// and reading level.
struct SettingsView: View {
    @Environment(ChatModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey = ""
    @State private var geminiKey = ""
    @State private var auth = AuthManager.shared
    @State private var subscriptions = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

    var body: some View {
        NavigationStack {
            Form {
                if AuthManager.isFirebaseConfigured {
                    accountSection
                    subscriptionSection
                }

                Section {
                    SecureField("sk-ant-…", text: $anthropicKey)
                        .font(.system(size: 17, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text(model.availableProviders.contains(.anthropic)
                         ? "A key is saved in the Keychain. Enter a new one to replace it."
                         : "Required for the Claude tutor — get a key at console.anthropic.com.")
                }

                Section {
                    SecureField("AIza…", text: $geminiKey)
                        .font(.system(size: 17, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Gemini API key")
                } footer: {
                    Text(model.availableProviders.contains(.gemini)
                         ? "A key is saved in the Keychain. Enter a new one to replace it."
                         : "Optional — enables the Gemini tutor as a second provider (aistudio.google.com).")
                }

                if model.availableProviders.count > 1 {
                    Section {
                        Picker("AI provider", selection: Binding(
                            get: { model.provider },
                            set: { model.provider = $0 }
                        )) {
                            ForEach(model.availableProviders) { provider in
                                Text(provider.label).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("AI provider")
                    } footer: {
                        // Explains what the *currently selected* option does —
                        // a static "which model teaches, quizzes..." caption
                        // left it unclear what picking "Built-in" specifically
                        // meant or required versus a personal API key.
                        Text(providerDescription(model.provider))
                    }
                }

                Section {
                    Picker("Reading level", selection: Binding(
                        get: { model.readingLevel },
                        set: { model.readingLevel = $0 }
                    )) {
                        ForEach(ReadingLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Reading level")
                } footer: {
                    Text("Sets the depth of lectures and the difficulty of quiz questions.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveKeys(
                            anthropic: anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            gemini: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                anthropicKey = Keychain.loadKey(.anthropic) ?? ""
                geminiKey = Keychain.loadKey(.gemini) ?? ""
            }
            .task {
                if AuthManager.isFirebaseConfigured, auth.isSignedIn {
                    await subscriptions.refreshStatus()
                    // refreshStatus() only pushes StoreKit status to Firestore
                    // and re-pulls the Pro flag — it doesn't refresh free-tier
                    // usage, so "Free lectures used" below could otherwise show
                    // a stale local count if another device used a slot since
                    // the last sync.
                    await subscriptions.syncWithFirestore()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }

    /// Explains what picking this provider actually does — shown as the AI
    /// provider picker's footer, describing the current selection rather
    /// than a generic caption that doesn't distinguish "uses your own key"
    /// from "uses Recall Tutor's built-in, metered tier."
    private func providerDescription(_ provider: AIProvider) -> String {
        switch provider {
        case .anthropic:
            return "Uses the Anthropic (Claude) API key you entered above. Never metered."
        case .gemini:
            return "Uses the Gemini API key you entered above. Never metered."
        case .firebase:
            return "Uses Recall Tutor's built-in AI — no API key needed. Free for your first \(SubscriptionManager.freeLectureLimit) lectures, then requires Recall Tutor Pro."
        }
    }

    // MARK: - Account (built-in tutor)

    private var accountSection: some View {
        Section {
            if auth.isSignedIn {
                LabeledContent("Signed in as", value: auth.email ?? auth.displayName ?? "Account")
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
            } else {
                Button {
                    auth.signInWithApple()
                } label: {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Sign in with Apple")
                        if auth.isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(auth.isLoading)
                Button {
                    auth.signInWithGoogle()
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                        if auth.isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(auth.isLoading)
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.appBody(size: 13))
                        .foregroundStyle(Theme.danger)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(auth.isSignedIn
                 ? "Your account unlocks the built-in tutor — no API key needed."
                 : "Sign in to use the built-in tutor without an API key (\(SubscriptionManager.freeLectureLimit) free lectures, then Recall Tutor Pro).")
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            if subscriptions.isPro {
                LabeledContent("Status", value: "Active")
                Button("Manage Subscription") {
                    showManageSubscriptions = true
                }
            } else if auth.isSignedIn {
                LabeledContent(
                    "Free lectures used",
                    value: "\(subscriptions.freeLecturesUsed) of \(SubscriptionManager.freeLectureLimit)"
                )
                Button("Subscribe to Recall Tutor Pro") {
                    showPaywall = true
                }
                Button("Restore Purchases") {
                    Task { await subscriptions.restore() }
                }
            }
            #if DEBUG
            // Opens the paywall regardless of sign-in/Pro/free-limit state —
            // for capturing the App Store Connect subscription review
            // screenshot without needing to actually exhaust free lectures.
            Button("Preview Paywall (dev)") {
                showPaywall = true
            }
            Toggle("Pro Override (dev)", isOn: $subscriptions.manualProOverrideEnabled)
            Button("Reset Free Lecture Count (dev)") {
                subscriptions.resetFreeUsage()
            }
            Button("Replay Onboarding (dev)") {
                UserDefaults.standard.set(false, forKey: "recalltutor_has_completed_onboarding")
            }
            #endif
        } header: {
            Text("Subscription")
        } footer: {
            Text(subscriptions.isPro
                 ? "Unlimited built-in lectures and quizzes. Cancellation takes effect at the end of the billing period."
                 : "Pro removes the \(SubscriptionManager.freeLectureLimit)-lecture limit on the built-in tutor. Your own API keys are never limited.")
        }
    }
}
