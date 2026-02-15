//
//  FirebaseManagerErrors.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

extension FirebaseManager {
    func isPermissionDeniedDescription(_ description: String) -> Bool {
        let lowercased = description.lowercased()
        return lowercased.contains("permission_denied") ||
            (lowercased.contains("permission") && lowercased.contains("denied")) ||
            lowercased.contains("erişim reddedildi")
    }

    func shouldLogObserverCancellation(_ error: Error) -> Bool {
        let description = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        if isPermissionDeniedDescription(description) {
            return false
        }
        if description.contains("not_mutual_pair") || description.contains("not mutual pair") {
            return false
        }
        if description.contains("mutual pairing is not active") ||
            description.contains("karşılıklı eşleşme aktif değil") {
            return false
        }
        return true
    }

    func mapAuthError(_ error: Error, action: String) -> Error {
        let nsError = error as NSError
        #if DEBUG
        print("FirebaseAuth \(action) hatası: domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
        #endif

        #if canImport(FirebaseAuth)
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return FirebaseManagerError.generic(L10n.f("firebase.auth.error.unexpected_format", action, nsError.localizedDescription))
        }

        switch code {
        case .invalidEmail:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.invalid_email"))
        case .emailAlreadyInUse:
            return FirebaseManagerError.generic(L10n.t("auth.error.email_in_use"))
        case .weakPassword:
            return FirebaseManagerError.generic(L10n.t("auth.error.password_policy"))
        case .wrongPassword:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.wrong_password"))
        case .userNotFound:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.user_not_found"))
        case .userDisabled:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.user_disabled"))
        case .tooManyRequests:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.too_many_requests"))
        case .networkError:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.network"))
        case .operationNotAllowed:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.operation_not_allowed"))
        case .appNotAuthorized:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.app_not_authorized"))
        case .internalError:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.internal"))
        default:
            return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
        }
        #else
        return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
        #endif
    }

    func mapDatabaseError(_ error: Error, path: String) -> Error {
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        let details = (nsError.userInfo["details"] as? String)?.lowercased() ?? ""
        let combined = "\(description) \(details)"
        #if DEBUG
        if !isPermissionDeniedDescription(combined) {
            print("RealtimeDatabase hatası path=\(path) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
        }
        #endif

        if combined.contains("permission_denied") || (combined.contains("permission") && combined.contains("denied")) {
            let normalizedPath = path.lowercased()
            if normalizedPath.contains("/chats/") || normalizedPath.contains("/events/") {
                return FirebaseManagerError.generic(L10n.t("pairing.request.error.not_mutual"))
            }
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.permission_denied_format", path))
        }
        if combined.contains("disconnected") {
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.disconnected_format", path))
        }
        if combined.contains("network") || combined.contains("offline") || combined.contains("timed out") {
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.network_format", path))
        }

        return FirebaseManagerError.generic(L10n.f("firebase.db.error.generic_format", path, nsError.localizedDescription))
    }

    func mapFunctionsError(_ error: Error, action: String) -> Error {
        let nsError = error as NSError
        #if DEBUG
        print("FirebaseFunctions hatası action=\(action) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
        #endif

        let detailsValue = nsError.userInfo["details"] ?? nsError.userInfo["FIRFunctionsErrorDetailsKey"]
        let detailDescription = String(describing: detailsValue ?? "").lowercased()
        let localizedDescription = nsError.localizedDescription.lowercased()
        let combined = "\(localizedDescription) \(detailDescription)"
        let isAcquireSessionAction = action == "acquireSessionLock"
        let isReleaseSessionAction = action == "releaseSessionLock"
        let isSessionAction = isAcquireSessionAction || isReleaseSessionAction
        let isChangePasswordAction = action == "changeMyPassword"
        let isDeleteMyAccountAction = action == "deleteMyAccount"

        if isAcquireSessionAction && combined.contains("session_lock_acquire_failed") {
            return FirebaseManagerError.sessionValidationFailed
        }
        if isReleaseSessionAction && combined.contains("session_lock_release_failed") {
            return FirebaseManagerError.logoutRequiresNetwork
        }

        #if canImport(FirebaseFunctions)
        if nsError.domain == FunctionsErrorDomain {
            if let code = FunctionsErrorCode(rawValue: nsError.code) {
                switch code {
                case .unauthenticated:
                    return FirebaseManagerError.unauthenticated
                case .invalidArgument:
                    if combined.contains("session_lock_invalid_installation") {
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    if isChangePasswordAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_policy"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if action == "ackMessageStored" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.invalid_ack_input"))
                    }
                    if action == "markMessageRead" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.read_receipt_invalid"))
                    }
                    if action == "setMessageReaction" || action == "clearMessageReaction" {
                        return FirebaseManagerError.generic(L10n.t("chat.reaction.error.invalid"))
                    }
                    if combined.contains("invalid_pair_code") {
                        return FirebaseManagerError.invalidPairCode
                    }
                    if combined.contains("self_pair_not_allowed") {
                        return FirebaseManagerError.generic(L10n.t("pairing.error.self_pair"))
                    }
                    return FirebaseManagerError.generic(L10n.t("pairing.request.error.generic_invalid"))
                case .failedPrecondition:
                    if combined.contains("session_locked_on_another_device") {
                        return FirebaseManagerError.sessionLockedElsewhere
                    }
                    if combined.contains("session_lock_invalid_installation") {
                        if isDeleteMyAccountAction {
                            return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_requires_active_device"))
                        }
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    if isChangePasswordAction {
                        if combined.contains("requires_recent_login") {
                            return FirebaseManagerError.generic(L10n.t("profile.management.error.reauth_required"))
                        }
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_policy"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if combined.contains("user_already_paired") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.user_already_paired"))
                    }
                    if combined.contains("target_already_paired") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.target_already_paired"))
                    }
                    if combined.contains("partner_not_found") {
                        return FirebaseManagerError.partnerNotFound
                    }
                    if combined.contains("request_expired") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.expired"))
                    }
                    if combined.contains("request_not_pending") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.not_pending"))
                    }
                    if combined.contains("duplicate_pending_unpair_request") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.notice.unpair_already_pending"))
                    }
                    if combined.contains("duplicate_pending_pair_request") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.duplicate_pending"))
                    }
                    if combined.contains("not_mutual_pair") {
                        return FirebaseManagerError.generic(L10n.t("pairing.request.error.not_mutual"))
                    }
                    if action == "ackMessageStored" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.ack_failed"))
                    }
                    if action == "markMessageRead" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.read_receipt_failed"))
                    }
                    if action == "setMessageReaction" || action == "clearMessageReaction" {
                        return FirebaseManagerError.generic(L10n.t("chat.reaction.error.failed"))
                    }
                    if action == "deleteConversationForUnpair" {
                        return FirebaseManagerError.generic(L10n.t("pairing.unpair.error.remote_delete_required"))
                    }
                    return FirebaseManagerError.generic(L10n.t("pairing.request.error.generic_invalid"))
                case .permissionDenied:
                    if isChangePasswordAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_change_failed"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if isSessionAction {
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    return FirebaseManagerError.generic(L10n.t("pairing.request.error.permission_denied"))
                case .notFound:
                    if isChangePasswordAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_change_failed"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if isSessionAction {
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    if action == "ackMessageStored" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.ack_failed"))
                    }
                    if action == "markMessageRead" {
                        return FirebaseManagerError.generic(L10n.t("chat.local.error.read_receipt_failed"))
                    }
                    if action == "setMessageReaction" || action == "clearMessageReaction" {
                        return FirebaseManagerError.generic(L10n.t("chat.reaction.error.failed"))
                    }
                    return FirebaseManagerError.generic(L10n.t("pairing.request.error.function_not_deployed"))
                case .unavailable, .deadlineExceeded:
                    if isChangePasswordAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_change_failed"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if isSessionAction {
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
                default:
                    if isChangePasswordAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.password_change_failed"))
                    }
                    if isDeleteMyAccountAction {
                        return FirebaseManagerError.generic(L10n.t("profile.management.error.delete_failed"))
                    }
                    if isSessionAction {
                        return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
                    }
                    return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
                }
            }
        }
        #endif

        if isSessionAction {
            return isReleaseSessionAction ? FirebaseManagerError.logoutRequiresNetwork : FirebaseManagerError.sessionValidationFailed
        }
        return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
    }
}
