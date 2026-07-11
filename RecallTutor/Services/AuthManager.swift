import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import SwiftUI

/// Manages Firebase Authentication state for Sign in with Apple and Google
/// Sign-In (ported from podchat's AuthManager).
///
/// Signing in unlocks the built-in (managed) Gemini tier — lectures without a
/// personal API key. Every operation no-ops with a helpful error when Firebase
/// isn't configured (no GoogleService-Info.plist in the bundle), so the app
/// keeps working in key-only mode until the console setup is done.
@MainActor @Observable
final class AuthManager: NSObject {
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

    // MARK: - Apple Sign-In state

    /// Nonce used for the current Apple Sign-In request.
    private var currentNonce: String?
    private var isConfigured = false

    private override init() {
        hasSkippedSignIn = UserDefaults.standard.bool(forKey: Self.skippedSignInKey)
        super.init()
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

    // MARK: - Sign in with Apple

    /// Initiates the Sign in with Apple flow.
    func signInWithApple() {
        guard Self.isFirebaseConfigured else {
            errorMessage = "Firebase isn't set up yet. Add GoogleService-Info.plist to the app (see FIREBASE.md)."
            return
        }
        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
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

    // MARK: - Helpers

    /// Generate a cryptographically secure random nonce for Apple Sign-In.
    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else { continue }

            for byte in randomBytes where remainingLength > 0 {
                let index = Int(byte) % charset.count
                result.append(charset[index])
                remainingLength -= 1
            }
        }

        return result
    }

    /// SHA-256 hash of the input string, returned as a hex string.
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            defer { isLoading = false }

            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleCredential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8)
            else {
                errorMessage = "Unable to retrieve Apple credentials."
                return
            }

            guard let nonce = currentNonce else {
                errorMessage = "Invalid state: no nonce found."
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                user = authResult.user
                hasSkippedSignIn = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            isLoading = false
            // Don't show error for user cancellation.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
