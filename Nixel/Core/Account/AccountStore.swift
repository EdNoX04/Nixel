import Foundation

/// Remembers whether the welcome screen has been seen.
///
/// Nixel has no accounts: the brief puts login and cloud sync out of scope, and the app's
/// premise is that nothing leaves the device. An earlier version offered an optional Sign
/// in with Apple and email, which stored details nothing used and, without a paid
/// developer account's capability, could only fail. Both are gone; this is all that's left.
@Observable
@MainActor
final class AccountStore {

    private let defaults = UserDefaults.standard
    private let seenKey = "welcome.seen"

    private(set) var hasSeenWelcome: Bool

    init() {
        hasSeenWelcome = defaults.bool(forKey: seenKey)
        // Details saved by the old optional sign-in are no longer used; don't keep them.
        defaults.removeObject(forKey: "welcome.identity")
        defaults.removeObject(forKey: "welcome.name")
    }

    func completeWelcome() {
        hasSeenWelcome = true
        defaults.set(true, forKey: seenKey)
    }
}
