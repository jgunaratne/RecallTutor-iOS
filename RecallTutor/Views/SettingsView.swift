import SwiftUI

private extension String {
    /// Whitespace-only counts as empty — a key field holding spaces has no key.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Settings sheet: account (Google sign-in for the built-in tutor),
/// subscription, provider API keys (Keychain-backed), AI provider choice,
/// and reading level.
struct SettingsView: View {
    @Environment(ChatModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey = ""
    @State private var geminiKey = ""
    @State private var openAIKey = ""
    @State private var auth = AuthManager.shared
    @State private var subscriptions = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    /// Provider selection is staged locally so a checkbox can be ticked for a
    /// key typed but not yet saved — committed with the keys on "Done".
    @State private var selected: AIProvider = .anthropic

    var body: some View {
        NavigationStack {
            Form {
                if AuthManager.isFirebaseConfigured {
                    accountSection
                    subscriptionSection
                }

                Section {
                    keyRow(.anthropic, placeholder: "sk-ant-…", text: $anthropicKey)
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text(anthropicKey.isBlank
                         ? "Required for the Claude tutor — get a key at console.anthropic.com."
                         : "Tick the box to teach with Claude. Enter a new key to replace the saved one.")
                }

                Section {
                    keyRow(.gemini, placeholder: "AIza…", text: $geminiKey)
                } header: {
                    Text("Gemini API key")
                } footer: {
                    Text(geminiKey.isBlank
                         ? "Optional — enables the Gemini tutor as a second provider (aistudio.google.com)."
                         : "Tick the box to teach with Gemini. Enter a new key to replace the saved one.")
                }

                Section {
                    keyRow(.openai, placeholder: "sk-…", text: $openAIKey)
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text(openAIKey.isBlank
                         ? "Optional — OpenAI generates lectures, quizzes, feedback, voice, and illustrations (platform.openai.com)."
                         : "Tick the box to teach with OpenAI — it also handles voice and illustrations.")
                }

                Section {
                    Text(providerDescription(selected))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                } header: {
                    Text("Using \(selected.label)")
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
                            gemini: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            openai: openAIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            selected: selected
                        )
                        dismiss()
                    }
                }
            }
            // Clearing the key of the ticked provider would otherwise leave a
            // checked-but-disabled box; move the tick to something usable.
            .onChange(of: anthropicKey) { deselectIfCleared(.anthropic, anthropicKey) }
            .onChange(of: geminiKey) { deselectIfCleared(.gemini, geminiKey) }
            .onChange(of: openAIKey) { deselectIfCleared(.openai, openAIKey) }
            .onAppear {
                anthropicKey = Keychain.loadKey(.anthropic) ?? ""
                geminiKey = Keychain.loadKey(.gemini) ?? ""
                openAIKey = Keychain.loadKey(.openai) ?? ""
                selected = model.provider
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

    // MARK: - Provider selection

    /// A key field with its "use this provider" checkbox in front. The box is
    /// only tickable once the field holds something — selecting a provider
    /// with no key would strand the tutor with no way to answer.
    private func keyRow(_ provider: AIProvider, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            checkbox(provider, isEnabled: !text.wrappedValue.isBlank)
            SecureField(placeholder, text: text)
                .font(.system(size: 17, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func checkbox(_ provider: AIProvider, isEnabled: Bool) -> some View {
        let isSelected = selected == provider
        return Button {
            selected = provider
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Theme.accent : Theme.borderSubtle)
        }
        // .plain keeps the tap target local — a Form row's default button
        // style would make the whole row (including the field) trigger it.
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Use \(provider.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func deselectIfCleared(_ provider: AIProvider, _ text: String) {
        guard selected == provider, text.isBlank else { return }
        if !anthropicKey.isBlank {
            selected = .anthropic
        } else if !geminiKey.isBlank {
            selected = .gemini
        } else if !openAIKey.isBlank {
            selected = .openai
        } else if FirebaseAIClient.isAvailable {
            selected = .firebase
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
        case .openai:
            return "Uses the OpenAI API key you entered above. Never metered."
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
                        .font(.footnote)
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
            HStack(spacing: 12) {
                checkbox(.firebase, isEnabled: FirebaseAIClient.isAvailable)
                Text("Use the built-in tutor")
            }
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
