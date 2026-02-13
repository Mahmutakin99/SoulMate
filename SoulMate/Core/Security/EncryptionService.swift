//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import CryptoKit
import Foundation

enum EncryptionError: Error {
    case missingIdentityKey
    case missingSharedKey
    case invalidPartnerPublicKey
    case invalidCiphertext
    case serializationFailed
}

final class EncryptionService {
    static let shared = EncryptionService(keychain: .shared)

    private let keychain: KeychainWrapper

    init(keychain: KeychainWrapper) {
        self.keychain = keychain
    }

    func identityPublicKeyBase64() throws -> String {
        let privateKey = try loadOrCreateIdentityPrivateKey()
        return Data(privateKey.publicKey.rawRepresentation).base64EncodedString()
    }

    func establishSharedKey(with partnerPublicKeyBase64: String, partnerUID: String) throws {
        guard let partnerPublicKeyData = Data(base64Encoded: partnerPublicKeyBase64) else {
            throw EncryptionError.invalidPartnerPublicKey
        }

        let privateKey = try loadOrCreateIdentityPrivateKey()
        let partnerPublicKey: Curve25519.KeyAgreement.PublicKey

        do {
            partnerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: partnerPublicKeyData)
        } catch {
            throw EncryptionError.invalidPartnerPublicKey
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: partnerPublicKey)

        // Sort both public keys so both peers derive the same salt deterministically.
        let localPublicKeyBase64 = Data(privateKey.publicKey.rawRepresentation).base64EncodedString()
        let partnerPublicKeyFingerprint = Data(partnerPublicKeyData).base64EncodedString()
        let hkdfSalt = [localPublicKeyBase64, partnerPublicKeyFingerprint].sorted().joined(separator: "|")
        let saltData = Data("SoulMate::\(hkdfSalt)".utf8)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: saltData,
            sharedInfo: Data("soulmate-chat-v1".utf8),
            outputByteCount: 32
        )

        let rawKey = symmetricKey.withUnsafeBytes { Data($0) }
        try keychain.save(rawKey, for: accountKeyForSharedKey(partnerUID: partnerUID))
    }

    func encrypt(_ plaintext: Data, for partnerUID: String) throws -> String {
        let key = try loadSharedKey(partnerUID: partnerUID)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealedBox.combined else {
            throw EncryptionError.serializationFailed
        }

        return combined.base64EncodedString()
    }

    func decrypt(_ ciphertextBase64: String, from partnerUID: String) throws -> Data {
        guard let combinedData = Data(base64Encoded: ciphertextBase64) else {
            throw EncryptionError.invalidCiphertext
        }

        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let key = try loadSharedKey(partnerUID: partnerUID)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func clearSharedKey(partnerUID: String) {
        try? keychain.delete(account: accountKeyForSharedKey(partnerUID: partnerUID))
    }

    private func loadSharedKey(partnerUID: String) throws -> SymmetricKey {
        guard let data = keychain.readIfPresent(account: accountKeyForSharedKey(partnerUID: partnerUID)) else {
            throw EncryptionError.missingSharedKey
        }
        return SymmetricKey(data: data)
    }

    private func loadOrCreateIdentityPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existingData = keychain.readIfPresent(account: identityPrivateKeyAccount) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existingData)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        try keychain.save(Data(privateKey.rawRepresentation), for: identityPrivateKeyAccount)
        return privateKey
    }

    private func accountKeyForSharedKey(partnerUID: String) -> String {
        "crypto.shared.\(normalized(partnerUID))"
    }

    // swiftlint:disable:next force_try
    private static let normalizeRegex = try! NSRegularExpression(pattern: "[^a-zA-Z0-9_-]")

    private func normalized(_ value: String) -> String {
        Self.normalizeRegex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: "_"
        )
    }

    private let identityPrivateKeyAccount = "crypto.identity.private"
}
