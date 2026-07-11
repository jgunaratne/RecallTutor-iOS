import FirebaseAuth
import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// Per-user records in Cloud Firestore (ported from podchat's
/// UserStatsService, trimmed to what Recall Tutor needs).
///
/// **Document** `recall-tutor-users/{uid}`:
/// - `uid`, `email`, `displayName` — profile, refreshed on each launch/sign-in
/// - `createdAt` — first seen (set once)
/// - `lastSeenAt` — most recent launch/sign-in
/// - `isPro` — whether the user has an active Pro subscription. Synced after
///   every StoreKit status check; can also be granted manually from the
///   Firebase console (the app honors a server-side `true`).
/// - `plan` — human-readable tier, `"pro"` or `"free"`. Written alongside
///   `isPro` (which remains the field the app reads).
/// - `subscriptionProductID`, `subscriptionUpdatedAt` — subscription detail
/// - `usedFreeLectureIDs`, `freeLecturesUsed` — free-tier usage, mirrored
///   server-side so it survives reinstalls and device changes
///
/// ⚠️ Requires the **FirebaseFirestore** SPM product on the app target. Until
/// it's added, every call here is a safe no-op so the app still builds.
enum UserStoreConstants {
    static let usersCollection = "recall-tutor-users"
    static let uid = "uid"
    static let email = "email"
    static let displayName = "displayName"
    static let createdAt = "createdAt"
    static let lastSeenAt = "lastSeenAt"
    static let isPro = "isPro"
    static let plan = "plan"
    static let planPro = "pro"
    static let planFree = "free"
    static let subscriptionProductID = "subscriptionProductID"
    static let subscriptionUpdatedAt = "subscriptionUpdatedAt"
    static let usedFreeLectureIDs = "usedFreeLectureIDs"
    static let freeLecturesUsed = "freeLecturesUsed"
}

@MainActor
final class UserStatsService {
    static let shared = UserStatsService()
    private init() {}

    #if canImport(FirebaseFirestore)
    /// The signed-in user's document, or `nil` when signed out or when
    /// Firebase isn't configured (no GoogleService-Info.plist).
    private var userDoc: DocumentReference? {
        guard AuthManager.isFirebaseConfigured,
              let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore()
            .collection(UserStoreConstants.usersCollection).document(uid)
    }
    #endif

    /// Upsert the signed-in user's profile. Sets `createdAt` only the first
    /// time the user is seen and refreshes profile + `lastSeenAt` thereafter.
    /// Safe to call on every sign-in and launch. No-op when signed out.
    func registerCurrentUser() {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc, let user = Auth.auth().currentUser else { return }

        var profile: [String: Any] = [
            UserStoreConstants.uid: user.uid,
            UserStoreConstants.lastSeenAt: FieldValue.serverTimestamp(),
        ]
        if let email = user.email { profile[UserStoreConstants.email] = email }
        if let name = user.displayName, !name.isEmpty { profile[UserStoreConstants.displayName] = name }

        doc.getDocument { snapshot, error in
            if let error {
                print("[UserStore] registerCurrentUser getDocument failed: \(error.localizedDescription)")
                return
            }
            var data = profile
            if snapshot?.exists != true {
                data[UserStoreConstants.createdAt] = FieldValue.serverTimestamp()
            }
            doc.setData(data, merge: true) { err in
                if let err {
                    print("[UserStore] registerCurrentUser setData failed: \(err.localizedDescription)")
                }
            }
        }
        #endif
    }

    /// Write the current subscription status to Firestore so the server
    /// record is always up-to-date. Called after every StoreKit refresh.
    func syncSubscriptionStatus(isPro: Bool, productID: String?) {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc else { return }
        var data: [String: Any] = [
            UserStoreConstants.isPro: isPro,
            UserStoreConstants.plan: isPro ? UserStoreConstants.planPro : UserStoreConstants.planFree,
            UserStoreConstants.subscriptionUpdatedAt: FieldValue.serverTimestamp(),
            UserStoreConstants.lastSeenAt: FieldValue.serverTimestamp(),
        ]
        if let productID { data[UserStoreConstants.subscriptionProductID] = productID }

        doc.setData(data, merge: true) { error in
            if let error {
                print("[UserStore] syncSubscriptionStatus failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Fetch the subscription status stored in Firestore. Returns `nil` if
    /// the document doesn't exist or the field is absent (new user).
    func fetchSubscriptionStatus() async -> Bool? {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc else { return nil }
        do {
            let snapshot = try await doc.getDocument()
            return snapshot.data()?[UserStoreConstants.isPro] as? Bool
        } catch {
            print("[UserStore] fetchSubscriptionStatus failed: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Record that a free-tier lecture slot was consumed. Writes the lecture
    /// ID into the Firestore array so usage is tracked server-side and
    /// survives reinstalls. Also updates the convenience count.
    func recordFreeLectureUse(lectureID: String, totalUsed: Int) {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc else { return }
        doc.setData(
            [
                UserStoreConstants.usedFreeLectureIDs: FieldValue.arrayUnion([lectureID]),
                UserStoreConstants.freeLecturesUsed: totalUsed,
                UserStoreConstants.lastSeenAt: FieldValue.serverTimestamp(),
            ],
            merge: true
        ) { error in
            if let error {
                print("[UserStore] recordFreeLectureUse failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Fetch the user's free-tier usage from Firestore. Called on sign-in so
    /// the local counter matches the server even after a reinstall or device
    /// change.
    func fetchUsedLectureIDs() async -> Set<String> {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc else { return [] }
        do {
            let snapshot = try await doc.getDocument()
            guard let ids = snapshot.data()?[UserStoreConstants.usedFreeLectureIDs] as? [String] else {
                return []
            }
            return Set(ids)
        } catch {
            print("[UserStore] fetchUsedLectureIDs failed: \(error.localizedDescription)")
            return []
        }
        #else
        return []
        #endif
    }

    /// Delete the signed-in user's document. For account deletion, so no
    /// personal data (email, name, subscription status, usage) remains.
    func deleteUserData() async {
        #if canImport(FirebaseFirestore)
        guard let doc = userDoc else { return }
        do {
            try await doc.delete()
        } catch {
            print("[UserStore] deleteUserData failed: \(error.localizedDescription)")
        }
        #endif
    }
}
