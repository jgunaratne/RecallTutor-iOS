import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import SwiftUI

/// Manages Firebase Authentication state for Google Sign-In (ported from
/// podchat's AuthManager, trimmed to the Google-only flow this app uses).
///
/// Signing in unlocks the built-in (managed) Gemini tier — lectures without a
/// personal API key. Every operation no-ops with a helpful error when Firebase
/// isn't configured (no GoogleService-Info.plist in the bundle), so the app
/// keeps working in key-only mode until the console setup is done.
@MainActor @Observable
final class AuthManager {
    static let shared = AuthManager()

    // MARK: - Published state

    /// The currently signed-in Firebase user, or `nil` if signed out.
    private(set) var user: User?

    /// Whether an authentication operation is in progress.
    private(set) var isLoading = false

    /// User-facing error message from the last failed operation.
    var errorMessage: String?

    /// Whether the user dismissed the sign-in prompt ("Not now"). Persisted so
    /// the prompt isn't shown again every launch. Cleared on sign-out.
    private static let skippedSignInKey = "recalltutor_skipped_sign_in"
    var hasSkippedSignIn: Bool {
        didSet { UserDefaults.standard.set(hasSkippedSignIn, forKey: Self.skippedSignInKey) }
    }

    // MARK: - Convenience accessors

    var isSignedIn: Bool { user != nil }
    var displayName: String? { user?.displayName ?? user?.providerData.compactMap(\.displayName).first }
    var email: String? { user?.email ?? user?.providerData.compactMap(\.email).first }

    /// Profile photo, falling back to any linked provider's photo.
    var photoURL: URL? { user?.photoURL ?? user?.providerData.compactMap(\.photoURL).first }

    /// True once FirebaseApp.configure() has run (GoogleService-Info.plist present).
    static var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }

    private var isConfigured = false

    private init() {
        hasSkippedSignIn = UserDefaults.standard.bool(forKey: Self.skippedSignInKey)
    }

    /// Must be called after `FirebaseApp.configure()`. Safe to call when
    /// Firebase isn't configured — it simply does nothing.
    func configure() {
        guard !isConfigured, Self.isFirebaseConfigured else { return }
        isConfigured = true
        user = Auth.auth().currentUser
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                self?.user = firebaseUser
                if firebaseUser != nil {
                    // Reload per-UID free-tier usage and entitlements so
                    // accounts on the same device stay isolated.
                    SubscriptionManager.shared.loadLocalUsage()
                    await SubscriptionManager.shared.refreshStatus()
                }
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        guard Self.isFirebaseConfigured else {
            errorMessage = "Firebase isn't set up yet. Add GoogleService-Info.plist to the app (see FIREBASE.md)."
            return
        }
        isLoading = true
        errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google Sign-In is not configured. Check your GoogleService-Info.plist."
            isLoading = false
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController
        else {
            errorMessage = "Unable to find root view controller."
            isLoading = false
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isLoading = false }

                if let error {
                    // Don't show error for user cancellation.
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                guard let idToken = result?.user.idToken?.tokenString else {
                    self.errorMessage = "Missing Google ID token."
                    return
                }

                let accessToken = result?.user.accessToken.tokenString ?? ""
                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: accessToken
                )

                do {
                    let authResult = try await Auth.auth().signIn(with: credential)
                    self.user = authResult.user
                    self.hasSkippedSignIn = false
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Sign out

    func signOut() {
        guard Self.isFirebaseConfigured else { return }
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            user = nil
            hasSkippedSignIn = false
            errorMessage = nil
            SubscriptionManager.shared.resetForSignOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
