import Foundation

/// Persists JWT token and user profile in UserDefaults.
/// Keeps ApiClient.shared.authToken in sync.
final class UserSession: ObservableObject {
    static let shared = UserSession()
    private init() { load() }

    private let defaults = UserDefaults.standard

    @Published var isLoggedIn = false
    @Published var profile: UserProfile?

    // MARK: Public API

    func save(token: String, profile: UserProfile) {
        defaults.set(token,                     forKey: "token")
        defaults.set(profile.id,               forKey: "user_id")
        defaults.set(profile.email,            forKey: "email")
        defaults.set(profile.vehicleType,      forKey: "vehicle_type")
        defaults.set(profile.isDisabled,       forKey: "is_disabled")
        defaults.set(profile.hasResidentPermit, forKey: "has_resident_permit")
        defaults.set(profile.residentZone,     forKey: "resident_zone")

        ApiClient.shared.authToken = token
        self.profile = profile
        self.isLoggedIn = true
    }

    func updateProfile(_ updated: UserProfile) {
        guard let token = defaults.string(forKey: "token") else { return }
        save(token: token, profile: updated)
    }

    func logout() {
        ["token", "user_id", "email", "vehicle_type",
         "is_disabled", "has_resident_permit", "resident_zone"].forEach {
            defaults.removeObject(forKey: $0)
        }
        ApiClient.shared.authToken = nil
        profile = nil
        isLoggedIn = false
    }

    // MARK: Private

    private func load() {
        guard let token = defaults.string(forKey: "token") else { return }
        ApiClient.shared.authToken = token
        profile = UserProfile(
            id: defaults.integer(forKey: "user_id"),
            email: defaults.string(forKey: "email") ?? "",
            vehicleType: defaults.string(forKey: "vehicle_type") ?? "car",
            isDisabled: defaults.bool(forKey: "is_disabled"),
            hasResidentPermit: defaults.bool(forKey: "has_resident_permit"),
            residentZone: defaults.string(forKey: "resident_zone") ?? ""
        )
        isLoggedIn = true
    }
}
