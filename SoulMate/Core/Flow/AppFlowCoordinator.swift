//
//  AppFlowCoordinator.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class AppFlowCoordinator {
    private enum LaunchResolutionSource {
        case strict
        case background
    }

    private let firebase: FirebaseManager
    private let launchRouteCache: LaunchRouteCache
    private weak var window: UIWindow?
    private var rootNavigationController: UINavigationController?
    private var activeLaunchRoute: CachedLaunchRoute?
    private var strictLaunchTimeoutWorkItem: DispatchWorkItem?
    private var strictLaunchFallbackTriggered = false
    private var isReconcilingLaunchState = false
    private var reconcileRetryWorkItem: DispatchWorkItem?
    private var reconcileRetryAttempt = 0
    private var lastTransitionNoticeAt: Date?

    init(firebase: FirebaseManager = .shared, launchRouteCache: LaunchRouteCache = .shared) {
        self.firebase = firebase
        self.launchRouteCache = launchRouteCache
    }

    func start(window: UIWindow) {
        self.window = window
        firebase.configureCoreIfNeeded()
        firebase.configureMessagingDelegateIfNeeded()
        ChatPerfLogger.mark("launch_t0_app_start")
        if shouldShowSplashOnLaunch {
            showSplashThenRoute()
        } else {
            routeOnLaunch(animated: false)
        }
    }

    func routeOnLaunch(animated: Bool = false, preferCachedRoute: Bool = true) {
        guard let uid = firebase.currentUserID() else {
            clearReconcileRetry()
            showAuth(animated: animated)
            return
        }

        if preferCachedRoute, routeImmediatelyFromCacheIfPossible(uid: uid, animated: animated) {
            ChatPerfLogger.mark("launch_t1_cached_route_applied")
            ChatPerfLogger.logDelta(
                from: "launch_t0_app_start",
                to: "launch_t1_cached_route_applied",
                context: "cached_route"
            )
            reconcileLaunchStateInBackground(animated: true)
            return
        }

        routeOnLaunchStrict(animated: animated)
    }

    private func routeOnLaunchStrict(animated: Bool) {
        strictLaunchTimeoutWorkItem?.cancel()
        strictLaunchFallbackTriggered = false
        if AppConfiguration.FeatureFlags.enableBalancedLaunchFallback,
           let uid = firebase.currentUserID() {
            let fallbackDelay = max(2.2, AppConfiguration.Session.lockCallTimeoutSeconds * 0.66)
            let fallbackWorkItem = DispatchWorkItem { [weak self] in
                self?.applyBalancedLaunchFallbackIfNeeded(uid: uid, animated: animated)
            }
            strictLaunchTimeoutWorkItem = fallbackWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fallbackWorkItem)
        }

        firebase.validateOrAcquireSessionForCurrentUser { [weak self] validation in
            DispatchQueue.main.async {
                switch validation {
                case .success:
                    self?.resolveAndRouteLaunchState(animated: animated, source: .strict)
                case .failure(let error):
                    self?.handleLaunchValidationFailure(error, animated: animated)
                }
            }
        }
    }

    private func resolveAndRouteLaunchState(animated: Bool, source: LaunchResolutionSource) {
        firebase.resolveLaunchState { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let state):
                    if source == .strict {
                        self.strictLaunchTimeoutWorkItem?.cancel()
                        self.strictLaunchFallbackTriggered = false
                    }
                    if source == .background {
                        self.clearReconcileRetry()
                        ChatPerfLogger.mark("launch_t2_background_validation_done")
                        ChatPerfLogger.logDelta(
                            from: "launch_t0_app_start",
                            to: "launch_t2_background_validation_done",
                            context: "background_reconcile"
                        )

                        self.launchRouteCache.save(state: state)
                        if self.isCurrentRouteMatching(state) {
                            self.applyRouteSideEffects(for: state)
                            return
                        }

                        self.route(for: state, animated: animated)
                        self.presentValidationChangedNoticeIfNeeded()
                    } else {
                        self.launchRouteCache.save(state: state)
                        self.route(for: state, animated: animated)
                    }
                case .failure(let error):
                    if source == .strict {
                        self.strictLaunchTimeoutWorkItem?.cancel()
                        self.strictLaunchFallbackTriggered = false
                    }
                    if source == .background, self.isTransientLaunchValidationError(error) {
                        self.scheduleReconcileRetry(animated: animated)
                        return
                    }

                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    #if DEBUG
                    print("Launch state resolution failed: \(message)")
                    #endif
                    self.showAuth(animated: animated, initialNoticeMessage: message)
                }
            }
        }
    }

    func showAuth(animated: Bool = false, initialNoticeMessage: String? = nil) {
        activeLaunchRoute = CachedLaunchRoute(kind: .unauthenticated, uid: nil, partnerUID: nil)
        let controller = AuthViewController()
        controller.initialNoticeMessage = initialNoticeMessage
        controller.onAuthSuccess = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        setRoot(controller, animated: animated)
    }

    func showPairingManagement() {
        guard let navigationController = rootNavigationController else {
            routeOnLaunch(animated: true)
            return
        }

        let controller = PairingViewController(autoOpenChatWhenPaired: false)
        controller.onBackToChat = { [weak navigationController] in
            navigationController?.popViewController(animated: true)
        }
        controller.onPaired = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        controller.onRequestSignOut = { [weak self] in
            self?.signOut()
        }
        navigationController.pushViewController(controller, animated: true)
    }

    func showProfileManagement() {
        guard let navigationController = rootNavigationController else {
            routeOnLaunch(animated: true)
            return
        }

        let controller = ProfileManagementViewController()
        controller.onSignedOut = { [weak self] in
            self?.showAuth(animated: true)
        }
        controller.onAccountDeleted = { [weak self] in
            self?.showAuth(animated: true)
        }
        navigationController.pushViewController(controller, animated: true)
    }

    func signOut() {
        let currentUID = firebase.currentUserID()
        firebase.signOutReleasingSession { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.launchRouteCache.clear(uid: currentUID)
                    self?.showAuth(animated: true)
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    #if DEBUG
                    print("Sign out failed: \(message)")
                    #endif
                    self?.presentTopAlert(message: message)
                }
            }
        }
    }

    private func showSplashThenRoute() {
        guard let window else { return }

        let splash = SplashViewController()
        splash.onFinished = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }

        let navigationController = UINavigationController(rootViewController: splash)
        navigationController.setNavigationBarHidden(true, animated: false)
        rootNavigationController = navigationController
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }

    private var shouldShowSplashOnLaunch: Bool {
        UserDefaults.standard.object(forKey: AppConfiguration.UserPreferenceKey.showsSplashOnLaunch) as? Bool ?? true
    }

    private func routeImmediatelyFromCacheIfPossible(uid: String, animated: Bool) -> Bool {
        guard let cached = launchRouteCache.load(uid: uid) else { return false }

        switch cached.kind {
        case .unauthenticated:
            showAuth(animated: animated)
        case .profile:
            showProfileCompletion(uid: cached.uid ?? uid, animated: animated)
        case .pairing:
            showPairingForLaunch(animated: animated, uid: cached.uid ?? uid)
        case .chat:
            showChat(animated: animated, uid: cached.uid ?? uid, partnerUID: cached.partnerUID)
        }
        return true
    }

    private func reconcileLaunchStateInBackground(animated: Bool) {
        guard firebase.currentUserID() != nil else {
            showAuth(animated: animated)
            return
        }
        guard !isReconcilingLaunchState else { return }

        isReconcilingLaunchState = true
        firebase.validateOrAcquireSessionForCurrentUser { [weak self] validation in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReconcilingLaunchState = false

                switch validation {
                case .success:
                    self.resolveAndRouteLaunchState(animated: animated, source: .background)
                case .failure(let error):
                    if self.isTransientLaunchValidationError(error) {
                        self.scheduleReconcileRetry(animated: animated)
                        return
                    }
                    self.handleLaunchValidationFailure(error, animated: animated)
                }
            }
        }
    }

    private func handleLaunchValidationFailure(_ error: Error, animated: Bool) {
        clearReconcileRetry()
        launchRouteCache.clear(uid: firebase.currentUserID())
        strictLaunchTimeoutWorkItem?.cancel()
        strictLaunchFallbackTriggered = false
        let message: String
        if let managerError = error as? FirebaseManagerError,
           case .sessionLockedElsewhere = managerError {
            message = L10n.t("auth.notice.launch_session_conflict")
        } else {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        showAuth(animated: animated, initialNoticeMessage: message)
    }

    private func isTransientLaunchValidationError(_ error: Error) -> Bool {
        if let managerError = error as? FirebaseManagerError {
            switch managerError {
            case .sessionLockedElsewhere:
                return false
            case .sessionValidationFailed, .logoutRequiresNetwork:
                return true
            default:
                break
            }
        }

        let description = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        return description.contains("network")
            || description.contains("offline")
            || description.contains("timed out")
            || description.contains("timeout")
            || description.contains("disconnected")
            || description.contains("unavailable")
            || description.contains("connection")
    }

    private func scheduleReconcileRetry(animated: Bool) {
        guard reconcileRetryAttempt < 6 else { return }
        reconcileRetryWorkItem?.cancel()

        let attempt = reconcileRetryAttempt
        reconcileRetryAttempt += 1
        let baseDelay = min(pow(2.0, Double(attempt)), 20)
        let jitter = Double.random(in: 0.85...1.2)
        let delay = baseDelay * jitter

        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileLaunchStateInBackground(animated: animated)
        }
        reconcileRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func clearReconcileRetry() {
        reconcileRetryWorkItem?.cancel()
        reconcileRetryWorkItem = nil
        reconcileRetryAttempt = 0
    }

    private func isCurrentRouteMatching(_ state: AppLaunchState) -> Bool {
        guard let activeLaunchRoute else { return false }
        return activeLaunchRoute.matches(state)
    }

    private func applyRouteSideEffects(for state: AppLaunchState) {
        if case .readyForChat = state {
            firebase.syncFCMTokenIfPossible()
            firebase.requestPushAuthorizationIfNeeded()
        }
    }

    private func applyBalancedLaunchFallbackIfNeeded(uid: String, animated: Bool) {
        guard !strictLaunchFallbackTriggered else { return }
        strictLaunchFallbackTriggered = true

        if let cached = launchRouteCache.load(uid: uid) {
            switch cached.kind {
            case .unauthenticated:
                showAuth(animated: animated)
            case .profile:
                showProfileCompletion(uid: cached.uid ?? uid, animated: animated)
            case .pairing:
                showPairingForLaunch(animated: animated, uid: cached.uid ?? uid)
            case .chat:
                showChat(animated: animated, uid: cached.uid ?? uid, partnerUID: cached.partnerUID)
            }
        } else {
            showPairingForLaunch(animated: animated, uid: uid)
        }
        reconcileLaunchStateInBackground(animated: true)
    }

    private func presentValidationChangedNoticeIfNeeded() {
        let now = Date()
        if let lastTransitionNoticeAt, now.timeIntervalSince(lastTransitionNoticeAt) < 5 {
            return
        }
        lastTransitionNoticeAt = now

        let isTurkish = Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true
        let message = isTurkish
            ? "Oturum doğrulandı ve ekran güncellendi."
            : "Session validated and screen was refreshed."
        presentTopAlert(message: message)
    }

    private func route(for state: AppLaunchState, animated: Bool) {
        launchRouteCache.save(state: state)
        if case .unauthenticated = state {
            // no-op
        } else {
            firebase.syncFCMTokenIfPossible()
        }

        switch state {
        case .unauthenticated:
            showAuth(animated: animated)

        case .needsProfileCompletion(let uid):
            showProfileCompletion(uid: uid, animated: animated)

        case .needsPairing(let uid, _):
            showPairingForLaunch(animated: animated, uid: uid)

        case .readyForChat(let uid, let partnerUID):
            firebase.requestPushAuthorizationIfNeeded()
            showChat(animated: animated, uid: uid, partnerUID: partnerUID)
        }
    }

    private func presentTopAlert(message: String) {
        guard !message.isEmpty else { return }
        guard let presenter = rootNavigationController?.topViewController else { return }
        guard presenter.presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: L10n.t("common.error_title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
        presenter.present(alert, animated: true)
    }

    private func showProfileCompletion(uid: String, animated: Bool) {
        activeLaunchRoute = CachedLaunchRoute(kind: .profile, uid: uid, partnerUID: nil)
        let viewModel = ProfileCompletionViewModel(uid: uid)
        let controller = ProfileCompletionViewController(viewModel: viewModel)
        controller.onProfileCompleted = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        setRoot(controller, animated: animated)
    }

    private func showPairingForLaunch(animated: Bool, uid: String?) {
        activeLaunchRoute = CachedLaunchRoute(kind: .pairing, uid: uid, partnerUID: nil)
        let controller = PairingViewController(autoOpenChatWhenPaired: true)
        controller.onPaired = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        controller.onRequestSignOut = { [weak self] in
            self?.signOut()
        }
        setRoot(controller, animated: animated)
    }

    private func showChat(animated: Bool, uid: String?, partnerUID: String?) {
        activeLaunchRoute = CachedLaunchRoute(kind: .chat, uid: uid, partnerUID: partnerUID)
        let controller = ChatViewController()
        controller.onRequestPairingManagement = { [weak self] in
            self?.showPairingManagement()
        }
        controller.onRequestProfileManagement = { [weak self] in
            self?.showProfileManagement()
        }
        controller.onRequirePairing = { [weak self] in
            self?.routeOnLaunch(animated: true, preferCachedRoute: false)
        }
        setRoot(controller, animated: animated)
    }

    private func setRoot(_ rootViewController: UIViewController, animated: Bool = false) {
        guard let window else { return }
        let navigationController = UINavigationController(rootViewController: rootViewController)
        rootNavigationController = navigationController

        if animated {
            UIView.transition(
                with: window,
                duration: 0.35,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    window.rootViewController = navigationController
                }
            )
        } else {
            window.rootViewController = navigationController
        }

        window.makeKeyAndVisible()
    }
}
