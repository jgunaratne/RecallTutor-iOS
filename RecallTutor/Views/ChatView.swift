import SwiftUI

/// Root screen — the iOS counterpart of components/Chat.tsx. Shows the home
/// greeting + topic chips when empty, the lecture stream otherwise, and
/// overlays the sidebar and full-screen quiz takeover.
struct ChatView: View {
    @Environment(ChatModel.self) private var model
    @State private var input = ""
    @State private var sidebarOpen = false
    @State private var showSettings = false
    @State private var subscriptions = SubscriptionManager.shared
    @State private var auth = AuthManager.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = model
        return ZStack {
            Theme.page.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if model.isEmpty {
                    HomeView(input: $input, inputFocused: $inputFocused, onSend: send)
                        .transition(.opacity)
                } else {
                    lectureArea
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.35), value: model.isEmpty)

            sidebarOverlay
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.quizSource != nil },
            set: { if !$0 { model.dismissQuiz() } }
        )) {
            if let source = model.quizSource {
                QuizTakeoverView(question: source.question, cards: source.cards)
                    .environment(model)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
        .sheet(isPresented: $model.showSignIn) {
            SignInSheet()
        }
        // Errors surface as a modal so they never disturb the layout.
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            if model.canRetry {
                Button("Retry") { model.retry() }
            }
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $subscriptions.showPaywall) {
            PaywallView(onOpenSettings: { showSettings = true })
        }
        .onAppear {
            let hasPersonalKey = model.availableProviders.contains(.anthropic)
                || model.availableProviders.contains(.gemini)
            if !model.hasAPIKey {
                // No key and no Firebase config — Settings is the only path.
                showSettings = true
            } else if !hasPersonalKey, !auth.isSignedIn, !auth.hasSkippedSignIn {
                // Built-in tier available but needs an account: offer sign-in.
                model.showSignIn = true
            }
        }
    }

    private func send() {
        let text = input
        input = ""
        model.sendMessage(text)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accentGradient)
                Text("Recall Tutor")
                    .font(.serifDisplay(size: 22))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { sidebarOpen = true }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Menu")

                Spacer()

                if !model.isEmpty {
                    Button {
                        model.newChat()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close lecture")
                } else {
                    // Home screen: account avatar (placeholder silhouette when
                    // signed out). Signed in → Settings (account section);
                    // signed out → the sign-in sheet.
                    Button {
                        if auth.isSignedIn {
                            showSettings = true
                        } else {
                            model.showSignIn = true
                        }
                    } label: {
                        UserAvatarView(photoURL: auth.photoURL, size: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(auth.isSignedIn
                                        ? "Account: \(auth.displayName ?? auth.email ?? "signed in")"
                                        : "Sign in")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - Lecture (full-screen card pager)

    private var lectureArea: some View {
        VStack(spacing: 0) {
            if let lastAssistant = model.messages.last(where: { $0.role == .assistant }) {
                LectureView(
                    message: lastAssistant,
                    isStreaming: model.isStreaming,
                    showQuizButton: model.showQuizButton,
                    onQuizMe: { model.startQuiz() }
                )
                // Reset the pager per exchange, not per streamed chunk.
                .id("\(model.activeId?.uuidString ?? "draft")-\(model.messages.count)")
            }
        }
    }

    // MARK: - Sidebar overlay

    @ViewBuilder
    private var sidebarOverlay: some View {
        if sidebarOpen {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { sidebarOpen = false }
                }
        }
        HStack(spacing: 0) {
            SidebarView(
                onClose: { withAnimation(.easeOut(duration: 0.2)) { sidebarOpen = false } },
                onOpenSettings: {
                    withAnimation(.easeOut(duration: 0.2)) { sidebarOpen = false }
                    showSettings = true
                }
            )
            .frame(width: 288)
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .offset(x: sidebarOpen ? 0 : -320)
            Spacer()
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// The shared message input card.
struct InputBar: View {
    @Binding var input: String
    let isStreaming: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var sendDisabled: Bool {
        isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What would you like to learn?", text: $input, axis: .vertical)
                .font(.appBody(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...5)
                .focused(focused)
                .disabled(isStreaming)
                .onSubmit(onSend)

            HStack {
                Spacer()
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accentGradient, in: .circle)
                        .opacity(sendDisabled ? 0.5 : 1.0)
                }
                .accessibilityLabel("Send")
                .disabled(sendDisabled)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
