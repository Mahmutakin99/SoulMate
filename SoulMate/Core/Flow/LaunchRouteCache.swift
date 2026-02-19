import Foundation

struct CachedLaunchRoute: Codable, Equatable {
    enum Kind: String, Codable {
        case unauthenticated
        case profile
        case pairing
        case chat
    }

    let kind: Kind
    let uid: String?
    let partnerUID: String?
    let cachedAt: TimeInterval

    init(kind: Kind, uid: String?, partnerUID: String?, cachedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.kind = kind
        self.uid = uid
        self.partnerUID = partnerUID
        self.cachedAt = cachedAt
    }

    init(state: AppLaunchState, cachedAt: TimeInterval = Date().timeIntervalSince1970) {
        switch state {
        case .unauthenticated:
            self.init(kind: .unauthenticated, uid: nil, partnerUID: nil, cachedAt: cachedAt)
        case .needsProfileCompletion(let uid):
            self.init(kind: .profile, uid: uid, partnerUID: nil, cachedAt: cachedAt)
        case .needsPairing(let uid, _):
            self.init(kind: .pairing, uid: uid, partnerUID: nil, cachedAt: cachedAt)
        case .readyForChat(let uid, let partnerUID):
            self.init(kind: .chat, uid: uid, partnerUID: partnerUID, cachedAt: cachedAt)
        }
    }

    func matches(_ state: AppLaunchState) -> Bool {
        switch (self.kind, state) {
        case (.unauthenticated, .unauthenticated):
            return true
        case (.profile, .needsProfileCompletion(let uid)):
            return self.uid == nil || self.uid == uid
        case (.pairing, .needsPairing(let uid, _)):
            return self.uid == nil || self.uid == uid
        case (.chat, .readyForChat(let uid, let partnerUID)):
            let uidMatches = self.uid == nil || self.uid == uid
            let partnerMatches = self.partnerUID == nil || self.partnerUID == partnerUID
            return uidMatches && partnerMatches
        default:
            return false
        }
    }
}

final class LaunchRouteCache {
    static let shared = LaunchRouteCache()

    private static let keyPrefix = "launch.route.cache"
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(state: AppLaunchState) {
        let route = CachedLaunchRoute(state: state)
        guard let uid = route.uid else { return }
        save(route: route, uid: uid)
    }

    func save(route: CachedLaunchRoute, uid: String) {
        guard !uid.isEmpty else { return }
        guard let data = try? encoder.encode(route) else { return }
        defaults.set(data, forKey: key(for: uid))
    }

    func load(uid: String) -> CachedLaunchRoute? {
        guard !uid.isEmpty else { return nil }
        let key = key(for: uid)
        guard let data = defaults.data(forKey: key),
              let route = try? decoder.decode(CachedLaunchRoute.self, from: data) else {
            return nil
        }

        let age = Date().timeIntervalSince1970 - route.cachedAt
        guard age <= Self.maxAge else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return route
    }

    func clear(uid: String?) {
        guard let uid, !uid.isEmpty else { return }
        defaults.removeObject(forKey: key(for: uid))
    }

    private func key(for uid: String) -> String {
        "\(Self.keyPrefix).\(uid)"
    }
}
