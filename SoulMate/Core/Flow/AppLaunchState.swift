import Foundation

enum AppLaunchState {
    case unauthenticated
    case needsProfileCompletion(uid: String)
    case needsPairing(uid: String, sixDigitUID: String)
    case readyForChat(uid: String, partnerUID: String)
}

