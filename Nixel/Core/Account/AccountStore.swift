import Foundation
import AuthenticationServices

/// Tracks whether the welcome screen has been passed, and who (if anyone) signed in.
///
/// Nixel does not need an account. The brief puts login and cloud sync out of scope, and
/// the app's whole premise is that nothing leaves the device — so signing in is offered,
/// never required, and unlocks nothing. This exists so the welcome screen appears once and
/// so a returning user is greeted by name if they chose to say who they are.
///
/// Nothing here is transmitted anywhere. The Apple credential is stored locally and used
/// only for the greeting.
@Observable
@MainActor
final class AccountStore {

    enum Identity: Equatable {
        case anonymous
        case apple(userID: String, name: String?)
        case email(String)

        var displayName: String? {
            switch self {
            case .anonymous: return nil
            case .apple(_, let name): return name
            case .email(let address): return address
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let seenKey = "welcome.seen"
    private let identityKey = "welcome.identity"
    private let nameKey = "welcome.name"

    private(set) var hasSeenWelcome: Bool
    private(set) var identity: Identity = .anonymous

    init() {
        hasSeenWelcome = defaults.bool(forKey: seenKey)
        if let stored = defaults.string(forKey: identityKey) {
            let name = defaults.string(forKey: nameKey)
            identity = stored.contains("@") ? .email(stored) : .apple(userID: stored, name: name)
        }
    }

    func completeWelcome() {
        hasSeenWelcome = true
        defaults.set(true, forKey: seenKey)
    }

    func signIn(_ identity: Identity) {
        self.identity = identity
        switch identity {
        case .anonymous:
            defaults.removeObject(forKey: identityKey)
            defaults.removeObject(forKey: nameKey)
        case .apple(let userID, let name):
            defaults.set(userID, forKey: identityKey)
            defaults.set(name, forKey: nameKey)
        case .email(let address):
            defaults.set(address, forKey: identityKey)
        }
        completeWelcome()
    }

    /// Reads an Apple credential. Nothing is sent anywhere; the identifier is kept locally
    /// so a returning user can be greeted, and that is all it is used for.
    func handleApple(_ result: Result<ASAuthorization, Error>) -> String? {
        switch result {
        case .success(let authorisation):
            guard let credential = authorisation.credential as? ASAuthorizationAppleIDCredential else {
                return "Couldn't read that sign-in."
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            signIn(.apple(userID: credential.user, name: name.isEmpty ? nil : name))
            return nil

        case .failure(let error):
            // A cancel is not an error worth shouting about.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return nil }
            // Sign in with Apple needs its capability enabled on the provisioning profile,
            // which a free Apple developer account cannot do. Say so plainly rather than
            // showing a raw error, and leave the other routes open.
            return "Sign in with Apple isn't set up for this build. You can continue without an account."
        }
    }
}
