import SwiftUI

/// Google sign-in prompt for the built-in tutor (ported from podchat's
/// SignInView). Shown when a user without an API key tries to generate a
/// lecture, and reachable from Settings. Signing in unlocks the built-in
/// Gemini tier (3 free lectures, then Recall Tutor Pro).
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var auth: AuthManager { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.08))
                        .frame(width: 150, height: 150)
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 112, height: 112)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Theme.accent)
                }

                VStack(spacing: 10) {
                    Text("Sign in to Recall Tutor")
                        .font(.serifDisplay(size: 26))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Signing in unlocks the built-in tutor — no API key needed. Your first \(SubscriptionManager.freeLectureLimit) lectures are free.")
                        .font(.appBody(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    auth.signInWithGoogle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20))
                        Text("Sign in with Google")
                            .font(.appBody(size: 17, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.accentGradient, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(auth.isLoading)

                if auth.isLoading {
                    ProgressView()
                        .padding(.top, 6)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.appBody(size: 13))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Button {
                    auth.hasSkippedSignIn = true
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.appBody(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Text("Without an account you can still use Recall Tutor with your own Anthropic or Gemini API key, added in Settings.")
                    .font(.appBody(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .background(Theme.page.ignoresSafeArea())
        .onChange(of: auth.isSignedIn) {
            if auth.isSignedIn { dismiss() }
        }
        .onAppear { auth.errorMessage = nil }
    }
}
