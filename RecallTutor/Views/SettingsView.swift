import SwiftUI

/// Settings sheet: provider API keys (Keychain-backed), AI provider choice,
/// and reading level.
struct SettingsView: View {
    @Environment(ChatModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey = ""
    @State private var geminiKey = ""

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("Which model teaches, quizzes, and reacts.")
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
        }
    }
}
