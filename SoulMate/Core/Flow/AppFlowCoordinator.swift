//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class AppFlowCoordinator {
    private let firebase: FirebaseManager
    private weak var window: UIWindow?
    private var rootNavigationController: UINavigationController?

    init(firebase: FirebaseManager = .shared) {
        self.firebase = firebase
    }

    func start(window: UIWindow) {
        self.window = window
        firebase.configureCoreIfNeeded()
        firebase.configureMessagingDelegateIfNeeded()
        if shouldShowSplashOnLaunch {
            showSplashThenRoute()
        } else {
            routeOnLaunch(animated: false)
        }
    }

    func routeOnLaunch(animated: Bool = false) {
        firebase.validateOrAcquireSessionForCurrentUser { [weak self] validation in
            DispatchQueue.main.async {
                switch validation {
                case .success:
                    self?.resolveAndRouteLaunchState(animated: animated)
                case .failure(let error):
                    let message: String
                    if let managerError = error as? FirebaseManagerError,
                       case .sessionLockedElsewhere = managerError {
                        message = L10n.t("auth.notice.launch_session_conflict")
                    } else {
                        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    self?.showAuth(animated: animated, initialNoticeMessage: message)
                }
            }
        }
    }

    private func resolveAndRouteLaunchState(animated: Bool) {
        firebase.resolveLaunchState { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let state):
                    self?.route(for: state, animated: animated)
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    #if DEBUG
                    print("Launch state resolution failed: \(message)")
                    #endif
                    self?.showAuth(animated: animated, initialNoticeMessage: message)
                }
            }
        }
    }

    func showAuth(animated: Bool = false, initialNoticeMessage: String? = nil) {
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

    func signOut() {
        firebase.signOutReleasingSession { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
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

    private func route(for state: AppLaunchState, animated: Bool) {
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

        case .needsPairing(_, _):
            showPairingForLaunch(animated: animated)

        case .readyForChat(_, _):
            firebase.requestPushAuthorizationIfNeeded()
            showChat(animated: animated)
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
        let viewModel = ProfileCompletionViewModel(uid: uid)
        let controller = ProfileCompletionViewController(viewModel: viewModel)
        controller.onProfileCompleted = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        setRoot(controller, animated: animated)
    }

    private func showPairingForLaunch(animated: Bool) {
        let controller = PairingViewController(autoOpenChatWhenPaired: true)
        controller.onPaired = { [weak self] in
            self?.routeOnLaunch(animated: true)
        }
        controller.onRequestSignOut = { [weak self] in
            self?.signOut()
        }
        setRoot(controller, animated: animated)
    }

    private func showChat(animated: Bool) {
        let controller = ChatViewController()
        controller.onRequestPairingManagement = { [weak self] in
            self?.showPairingManagement()
        }
        controller.onRequestSignOut = { [weak self] in
            self?.signOut()
        }
        controller.onRequirePairing = { [weak self] in
            self?.routeOnLaunch(animated: true)
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
