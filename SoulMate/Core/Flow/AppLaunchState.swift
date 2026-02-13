//
//  AppLaunchState.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation

enum AppLaunchState {
    case unauthenticated
    case needsProfileCompletion(uid: String)
    case needsPairing(uid: String, sixDigitUID: String)
    case readyForChat(uid: String, partnerUID: String)
}

