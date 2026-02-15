//
//  KeychainWrapper.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case unhandledStatus(OSStatus)
}

final class KeychainWrapper {
    static let shared = KeychainWrapper(
        service: AppConfiguration.keychainService,
        accessGroup: AppConfiguration.keychainAccessGroup
    )

    private let service: String
    private let accessGroup: String?
    private var canUseAccessGroup: Bool

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        let normalized = accessGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessGroup = (normalized?.isEmpty == false) ? normalized : nil
        self.canUseAccessGroup = self.accessGroup != nil
    }

    func save(_ data: Data, for account: String) throws {
        let query = activeBaseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { $1 }) as CFDictionary, nil)
        if status == errSecMissingEntitlement, canUseAccessGroup {
            canUseAccessGroup = false
            try save(data, for: account)
            return
        }

        if status == errSecDuplicateItem {
            try update(data, for: account)
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func update(_ data: Data, for account: String) throws {
        let query = activeBaseQuery(for: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecMissingEntitlement, canUseAccessGroup {
            canUseAccessGroup = false
            try update(data, for: account)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func read(account: String) throws -> Data {
        var query = activeBaseQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecMissingEntitlement, canUseAccessGroup {
            canUseAccessGroup = false
            return try read(account: account)
        }

        if status == errSecItemNotFound, canUseAccessGroup {
            var fallbackQuery = baseQuery(for: account, includeAccessGroup: false)
            fallbackQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            fallbackQuery[kSecReturnData as String] = true

            var fallbackResult: CFTypeRef?
            let fallbackStatus = SecItemCopyMatching(fallbackQuery as CFDictionary, &fallbackResult)
            if fallbackStatus == errSecSuccess, let fallbackData = fallbackResult as? Data {
                return fallbackData
            }
        }

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    func readIfPresent(account: String) -> Data? {
        return try? read(account: account)
    }

    func delete(account: String) throws {
        let status = SecItemDelete(activeBaseQuery(for: account) as CFDictionary)

        if status == errSecMissingEntitlement, canUseAccessGroup {
            canUseAccessGroup = false
            try delete(account: account)
            return
        }

        var fallbackStatus: OSStatus = errSecSuccess
        if canUseAccessGroup {
            fallbackStatus = SecItemDelete(baseQuery(for: account, includeAccessGroup: false) as CFDictionary)
        }

        let acceptable = [errSecSuccess, errSecItemNotFound]
        guard acceptable.contains(status) || acceptable.contains(fallbackStatus) else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func deleteAll(accountPrefix: String) throws {
        let trimmedPrefix = accountPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty else { return }

        var accounts = try listAccounts(includeAccessGroup: canUseAccessGroup)
        if canUseAccessGroup {
            let fallbackAccounts = try listAccounts(includeAccessGroup: false)
            accounts.append(contentsOf: fallbackAccounts)
        }

        let uniqueAccounts = Set(accounts.filter { $0.hasPrefix(trimmedPrefix) })
        for account in uniqueAccounts {
            try delete(account: account)
        }
    }

    func save(string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        try save(data, for: account)
    }

    func readString(account: String) throws -> String {
        let data = try read(account: account)
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    private func activeBaseQuery(for account: String) -> [String: Any] {
        baseQuery(for: account, includeAccessGroup: canUseAccessGroup)
    }

    private func baseQuery(for account: String, includeAccessGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if includeAccessGroup, let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func listAccounts(includeAccessGroup: Bool) throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        if includeAccessGroup, let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        if status == errSecMissingEntitlement, includeAccessGroup {
            return []
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
