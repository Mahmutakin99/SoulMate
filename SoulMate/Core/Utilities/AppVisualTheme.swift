//
//  AppVisualTheme.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 13/02/2026.
//

import UIKit

enum AppVisualTheme {
    static let backgroundBase = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
    static let gradientColors: [UIColor] = [
        UIColor(red: 0.12, green: 0.08, blue: 0.12, alpha: 1),
        UIColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 1),
        UIColor(red: 0.07, green: 0.13, blue: 0.14, alpha: 1)
    ]
    static let softCardBackground = UIColor(red: 0.14, green: 0.14, blue: 0.18, alpha: 0.9)
    static let fieldBackground = UIColor(red: 0.15, green: 0.15, blue: 0.19, alpha: 1)
    static let fieldBorder = UIColor(red: 0.36, green: 0.36, blue: 0.42, alpha: 1)
    static let textPrimary = UIColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1)
    static let textSecondary = UIColor(red: 0.78, green: 0.78, blue: 0.84, alpha: 1)
    static let accent = UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 1)

    static func applyBackground(to view: UIView, gradientLayer: CAGradientLayer) {
        view.backgroundColor = backgroundBase
        gradientLayer.colors = gradientColors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)

        if gradientLayer.superlayer == nil {
            view.layer.insertSublayer(gradientLayer, at: 0)
        }
        gradientLayer.frame = view.bounds
    }
}
