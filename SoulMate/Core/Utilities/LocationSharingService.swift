//
//  LocationSharingService.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import CoreLocation
import Foundation

final class LocationSharingService: NSObject {
    var onLocationUpdate: ((CLLocation) -> Void)?
    var onAuthorizationDenied: (() -> Void)?
    var onDistanceUpdate: ((Double) -> Void)?

    private let manager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var partnerLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 20
    }

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            onAuthorizationDenied?()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func updatePartnerLocation(latitude: Double, longitude: Double) {
        partnerLocation = CLLocation(latitude: latitude, longitude: longitude)
        computeDistanceIfPossible()
    }

    func clearPartnerLocation() {
        partnerLocation = nil
    }

    private func computeDistanceIfPossible() {
        guard let current = currentLocation,
              let partnerLocation else {
            return
        }

        let meters = current.distance(from: partnerLocation)
        onDistanceUpdate?(meters / 1_000)
    }
}

extension LocationSharingService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            onAuthorizationDenied?()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        onLocationUpdate?(location)
        computeDistanceIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
    }
}
