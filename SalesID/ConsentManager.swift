import Foundation

final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()

    @Published var isAccepted: Bool
    @Published var scopeAllCalls: Bool
    @Published var hasOnboarded: Bool

    private let acceptedKey = "consent.accepted"
    private let scopeKey = "consent.scope_all"
    private let onboardedKey = "consent.onboarded"

    private init() {
        let defaults = UserDefaults.standard
        self.isAccepted = defaults.bool(forKey: acceptedKey)
        self.scopeAllCalls = defaults.bool(forKey: scopeKey)
        self.hasOnboarded = defaults.bool(forKey: onboardedKey)
    }

    func accept(scopeAll: Bool) {
        scopeAllCalls = scopeAll
        isAccepted = true
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: acceptedKey)
        defaults.set(scopeAll, forKey: scopeKey)
        defaults.set(true, forKey: onboardedKey)
        hasOnboarded = true
    }

    func decline() {
        scopeAllCalls = false
        isAccepted = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: acceptedKey)
        defaults.removeObject(forKey: scopeKey)
        defaults.removeObject(forKey: onboardedKey)
        hasOnboarded = false
    }

    var shouldShowConsent: Bool { !hasOnboarded || !isAccepted }
}


