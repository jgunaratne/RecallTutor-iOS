import FirebaseAuth
import StoreKit

/// Product identifiers for the app's subscriptions.
enum SubscriptionProduct {
    /// Must match the product ID configured in App Store Connect (and any
    /// local .storekit configuration). See FIREBASE.md.
    static let proMonthly = "com.gunaratne.recalltutor.promonthly"
}

/// Manages the Recall Tutor Pro subscription (StoreKit 2) **and** the
/// free-tier allowance for the built-in Gemini tier (ported from podchat's
/// SubscriptionManager).
///
/// The built-in (no API key) tier is funded by us, so it's metered: a user may
/// generate lectures for up to ``freeLectureLimit`` distinct lectures for
/// free. Beyond that they must either subscribe to Pro or supply their own
/// API key in Settings (which is never metered).
@MainActor @Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    /// Number of distinct lectures a user may generate on the built-in tier
    /// before a subscription or personal API key is required.
    static let freeLectureLimit = 3

    private static let usedFreeLectureIDsBase = "recalltutor_used_free_lecture_ids"
    private static let manualProOverrideKey = "recalltutor_manual_pro_override"

    /// Development-only access switch. Compiled out of release builds so no
    /// stray UserDefaults flag can ever grant Pro in the shipping app.
    #if DEBUG
    var manualProOverrideEnabled = UserDefaults.standard.bool(forKey: SubscriptionManager.manualProOverrideKey) {
        didSet {
            UserDefaults.standard.set(manualProOverrideEnabled, forKey: Self.manualProOverrideKey)
        }
    }
    #else
    let manualProOverrideEnabled = false
    #endif

    /// Whether the user has active Pro access. Pro is account-bound: a
    /// signed-out user is never Pro, even though a StoreKit entitlement
    /// persists at the Apple-ID level.
    var isPro: Bool {
        guard AuthManager.shared.isSignedIn else { return false }
        return hasActiveSubscription || manualProOverrideEnabled
    }

    /// True when StoreKit reports a current, non-revoked entitlement to Pro.
    private(set) var hasActiveSubscription = false

    /// Available products from the App Store / StoreKit configuration.
    var products: [Product] = []

    var isLoading = false
    var errorMessage: String?

    /// Drives the paywall sheet.
    var showPaywall = false

    // MARK: - Free-tier usage

    /// IDs of lectures (conversations) that have already consumed a slot of
    /// the free built-in allowance. Persisted so the count survives relaunches.
    private(set) var usedFreeLectureIDs: Set<String> = []

    /// UserDefaults key namespaced to the current Firebase UID so different
    /// accounts on the same device never share free-tier usage data.
    private var usedLectureIDsKey: String {
        let uid = AuthManager.isFirebaseConfigured
            ? (Auth.auth().currentUser?.uid ?? "anonymous")
            : "anonymous"
        return "\(Self.usedFreeLectureIDsBase)_\(uid)"
    }

    /// How many of the free lectures have been used.
    var freeLecturesUsed: Int { usedFreeLectureIDs.count }

    /// How many free lectures remain (never negative).
    var freeLecturesRemaining: Int { max(0, Self.freeLectureLimit - freeLecturesUsed) }

    /// True once the free allowance is exhausted (independent of Pro status).
    var hasReachedFreeLimit: Bool { freeLecturesUsed >= Self.freeLectureLimit }

    /// Load the free-lecture cache for the currently signed-in user.
    func loadLocalUsage() {
        let stored = UserDefaults.standard.stringArray(forKey: usedLectureIDsKey) ?? []
        usedFreeLectureIDs = Set(stored)
    }

    /// Record built-in-tier use of a lecture and enforce the free limit.
    ///
    /// - Returns: `true` if the lecture is allowed to use the built-in tier.
    ///   `false` means the allowance is exhausted for a *new* lecture — the
    ///   caller should surface the paywall.
    /// - Note: Continuing an already-counted lecture never consumes a new
    ///   slot, so follow-ups and quizzes on a free lecture stay free.
    @discardableResult
    func registerManagedLectureUse(lectureID: String) -> Bool {
        // The built-in (we-fund) tier is account-bound.
        guard AuthManager.shared.isSignedIn else { return false }

        // Pro users (or the dev override) are never metered.
        guard !isPro else { return true }

        // Already counted → always allowed, no new slot consumed.
        if usedFreeLectureIDs.contains(lectureID) { return true }

        // New lecture but no headroom left → block (caller surfaces the paywall).
        if hasReachedFreeLimit { return false }

        // New lecture with headroom → consume a slot.
        usedFreeLectureIDs.insert(lectureID)
        UserDefaults.standard.set(Array(usedFreeLectureIDs), forKey: usedLectureIDsKey)
        return true
    }

    /// Reset the free allowance. Used by the DEBUG settings tools.
    func resetFreeUsage() {
        usedFreeLectureIDs = []
        UserDefaults.standard.removeObject(forKey: usedLectureIDsKey)
    }

    // MARK: - StoreKit

    private var updateTask: Task<Void, Never>?

    private init() {
        loadLocalUsage()
        updateTask = Task {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await refreshStatus()
                    await transaction.finish()
                }
            }
        }
    }

    /// Load products and check subscription status.
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [SubscriptionProduct.proMonthly])
            await refreshStatus()
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    /// Purchase the Pro subscription.
    func purchase() async {
        guard let product = products.first else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = try? verification.payloadValue {
                    await transaction.finish()
                    await refreshStatus()
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Restore purchases.
    func restore() async {
        isLoading = true
        defer { isLoading = false }

        try? await AppStore.sync()
        await refreshStatus()
    }

    /// Check if the user has an active subscription.
    func refreshStatus() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.productID == SubscriptionProduct.proMonthly,
               transaction.revocationDate == nil
            {
                hasActive = true
                break
            }
        }
        hasActiveSubscription = hasActive
    }

    /// Clear subscription state on sign-out so the next sign-in starts fresh.
    /// The UID-namespaced usage key stays on disk so the same user can sign
    /// back in and recover their local count.
    func resetForSignOut() {
        hasActiveSubscription = false
        products = []
        errorMessage = nil
        showPaywall = false
        usedFreeLectureIDs = []
    }
}
