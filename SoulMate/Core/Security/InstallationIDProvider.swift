//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation

final class InstallationIDProvider {
    static let shared = InstallationIDProvider()

    private let keychain: KeychainWrapper
    private let defaults: UserDefaults
    private let account: String
    private let fallbackDefaultsKey = "session.installation_id.fallback"

    init(
        keychain: KeychainWrapper = .shared,
        defaults: UserDefaults = .standard,
        account: String = AppConfiguration.Session.installationIDAccount
    ) {
        self.keychain = keychain
        self.defaults = defaults
        self.account = account
    }

    func installationID() -> String {
        if let existing = try? keychain.readString(account: account),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        if let fallback = defaults.string(forKey: fallbackDefaultsKey),
           !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? keychain.save(string: fallback, for: account)
            return fallback
        }

        let generated = UUID().uuidString.lowercased()
        try? keychain.save(string: generated, for: account)
        defaults.set(generated, forKey: fallbackDefaultsKey)
        return generated
    }
}
