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
                    self?.showAuth(animated: animated)
                }
            }
        }
    }

    func showAuth(animated: Bool = false) {
        let controller = AuthViewController()
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
        do {
            try firebase.signOut()
            showAuth(animated: true)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            #if DEBUG
            print("Sign out failed: \(message)")
            #endif
            showAuth(animated: true)
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
