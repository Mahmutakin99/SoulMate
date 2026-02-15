//
//  SplashViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class SplashViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let totalDuration: TimeInterval = 0.10
    private let travelDuration: TimeInterval = 0.75

    private let backgroundView = UIView()
    private let backgroundGradientLayer = CAGradientLayer()
    private let leftOrbView = UIView()
    private let rightOrbView = UIView()
    private let logoContainerView = UIView()
    private let logoImageView = UIImageView()
    private let titleLabel = UILabel()

    private let leftGradientLayer = CAGradientLayer()
    private let rightGradientLayer = CAGradientLayer()

    private var hasStartedAnimation = false
    private var hasScheduledFinish = false
    private var orbDiameter: CGFloat = 140

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundGradientLayer.frame = backgroundView.bounds
        layoutOrbsForCurrentBounds()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStartedAnimation else { return }
        startAnimationSequence()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 15/255, green: 16/255, blue: 34/255, alpha: 1)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .clear
        view.addSubview(backgroundView)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        backgroundGradientLayer.colors = [
            UIColor(red: 15/255, green: 16/255, blue: 34/255, alpha: 1).cgColor,
            UIColor(red: 26/255, green: 29/255, blue: 58/255, alpha: 1).cgColor,
            UIColor(red: 12/255, green: 58/255, blue: 71/255, alpha: 1).cgColor
        ]
        backgroundGradientLayer.locations = [0.0, 0.55, 1.0]
        backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        backgroundView.layer.insertSublayer(backgroundGradientLayer, at: 0)

        leftOrbView.backgroundColor = .clear
        leftOrbView.clipsToBounds = true
        leftOrbView.layer.cornerRadius = 20
        rightOrbView.backgroundColor = .clear
        rightOrbView.clipsToBounds = true
        rightOrbView.layer.cornerRadius = 20
        backgroundView.addSubview(leftOrbView)
        backgroundView.addSubview(rightOrbView)

        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.alpha = 0
        logoContainerView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        backgroundView.addSubview(logoContainerView)

        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.isAccessibilityElement = true
        logoImageView.accessibilityLabel = L10n.t("app.name")
        logoImageView.image = UIImage(named: "SplashLogo") ?? UIImage(systemName: "heart.circle.fill")
        logoImageView.tintColor = UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 1)
        logoContainerView.addSubview(logoImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L10n.t("splash.title")
        titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 21) ?? .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1, alpha: 0.92)
        titleLabel.textAlignment = .center
        titleLabel.alpha = 0
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 8)
        backgroundView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            logoContainerView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            logoContainerView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor, constant: -24),
            logoContainerView.widthAnchor.constraint(equalToConstant: 128),
            logoContainerView.heightAnchor.constraint(equalToConstant: 128),

            logoImageView.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            logoImageView.bottomAnchor.constraint(equalTo: logoContainerView.bottomAnchor),
            logoImageView.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            logoImageView.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: logoContainerView.bottomAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backgroundView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: backgroundView.trailingAnchor, constant: -20)
        ])

        leftOrbView.layer.insertSublayer(leftGradientLayer, at: 0)
        rightOrbView.layer.insertSublayer(rightGradientLayer, at: 0)

        leftGradientLayer.colors = [
            UIColor(red: 0.36, green: 0.42, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.55, green: 0.30, blue: 1.0, alpha: 1).cgColor
        ]
        leftGradientLayer.startPoint = CGPoint(x: 0.15, y: 0.15)
        leftGradientLayer.endPoint = CGPoint(x: 0.85, y: 0.85)

        rightGradientLayer.colors = [
            UIColor(red: 1.0, green: 0.30, blue: 0.62, alpha: 1).cgColor,
            UIColor(red: 0.71, green: 0.30, blue: 1.0, alpha: 1).cgColor
        ]
        rightGradientLayer.startPoint = CGPoint(x: 0.15, y: 0.15)
        rightGradientLayer.endPoint = CGPoint(x: 0.85, y: 0.85)
    }

    private func layoutOrbsForCurrentBounds() {
        let targetSize = min(max(view.bounds.width * 0.34, 120), 160)
        let sizeChanged = abs(targetSize - orbDiameter) > 0.5
        if sizeChanged {
            orbDiameter = targetSize
        }

        let orbRadius = orbDiameter / 2
        leftOrbView.bounds = CGRect(x: 0, y: 0, width: orbDiameter, height: orbDiameter)
        rightOrbView.bounds = CGRect(x: 0, y: 0, width: orbDiameter, height: orbDiameter)

        leftOrbView.layer.cornerRadius = orbRadius
        rightOrbView.layer.cornerRadius = orbRadius

        if sizeChanged || leftOrbView.layer.shadowPath == nil {
            [leftOrbView, rightOrbView].forEach {
                $0.layer.shadowColor = UIColor.black.cgColor
                $0.layer.shadowOpacity = 0.18
                $0.layer.shadowRadius = 14
                $0.layer.shadowOffset = CGSize(width: 0, height: 8)
                $0.layer.shadowPath = UIBezierPath(
                    roundedRect: $0.bounds,
                    cornerRadius: orbRadius
                ).cgPath
            }
        }

        if !hasStartedAnimation {
            leftOrbView.center = CGPoint(x: -orbRadius, y: view.bounds.maxY + orbRadius)
            rightOrbView.center = CGPoint(x: view.bounds.maxX + orbRadius, y: view.bounds.maxY + orbRadius)
            leftOrbView.alpha = 1
            rightOrbView.alpha = 1
            leftOrbView.transform = .identity
            rightOrbView.transform = .identity
        }

        leftGradientLayer.frame = leftOrbView.bounds
        rightGradientLayer.frame = rightOrbView.bounds
    }

    private func startAnimationSequence() {
        hasStartedAnimation = true
        view.layoutIfNeeded()

        let fusionCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY - 24)
        let leftTarget = CGPoint(x: fusionCenter.x - orbDiameter * 0.18, y: fusionCenter.y)
        let rightTarget = CGPoint(x: fusionCenter.x + orbDiameter * 0.18, y: fusionCenter.y)

        let leftPath = UIBezierPath()
        leftPath.move(to: leftOrbView.layer.position)
        leftPath.addCurve(
            to: leftTarget,
            controlPoint1: CGPoint(x: view.bounds.width * 0.14, y: view.bounds.height * 0.60),
            controlPoint2: CGPoint(x: fusionCenter.x - orbDiameter * 0.62, y: fusionCenter.y - orbDiameter * 0.44)
        )

        let rightPath = UIBezierPath()
        rightPath.move(to: rightOrbView.layer.position)
        rightPath.addCurve(
            to: rightTarget,
            controlPoint1: CGPoint(x: view.bounds.width * 0.86, y: view.bounds.height * 0.60),
            controlPoint2: CGPoint(x: fusionCenter.x + orbDiameter * 0.62, y: fusionCenter.y - orbDiameter * 0.44)
        )

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.performFusionReveal()
        }

        animateOrb(layer: leftOrbView.layer, path: leftPath, finalPosition: leftTarget)
        animateOrb(layer: rightOrbView.layer, path: rightPath, finalPosition: rightTarget)

        CATransaction.commit()

        if !hasScheduledFinish {
            hasScheduledFinish = true
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
                self?.onFinished?()
            }
        }
    }

    private func animateOrb(layer: CALayer, path: UIBezierPath, finalPosition: CGPoint) {
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = path.cgPath
        animation.duration = travelDuration
        animation.calculationMode = .paced
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        layer.position = finalPosition
        layer.add(animation, forKey: "splash.position")
    }

    private func performFusionReveal() {
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut], animations: {
            self.leftOrbView.alpha = 0
            self.rightOrbView.alpha = 0
            self.leftOrbView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.rightOrbView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        })

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.35,
            options: [.curveEaseOut]
        ) {
            self.logoContainerView.alpha = 1
            self.logoContainerView.transform = .identity
        }

        UIView.animate(withDuration: 0.28, delay: 0.08, options: [.curveEaseOut]) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
        }
    }
}
