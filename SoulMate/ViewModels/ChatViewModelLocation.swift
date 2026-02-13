//
//  ChatViewModelLocation.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

extension ChatViewModel {
    func shareDistance(kilometers: Double) {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard let currentUserID,
              let partnerUserID else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_distance")))
            return
        }

        do {
            let value = String(format: "%.2f", kilometers)
            let encrypted = try encryption.encrypt(Data(value.utf8), for: partnerUserID)
            firebase.updateLocationCiphertext(uid: currentUserID, ciphertext: encrypted) { [weak self] result in
                if case .failure(let error) = result {
                    self?.emitError(error)
                }
            }
            persistWidgetDistance("\(value) km")
        } catch {
            emitError(error)
        }
    }

    func handlePartnerLocationCiphertext(_ ciphertext: String?) {
        guard let ciphertext,
              let partnerUserID,
              !ciphertext.isEmpty else {
            notifyOnMain {
                self.onDistanceUpdated?(nil)
            }
            return
        }

        do {
            let decrypted = try encryption.decrypt(ciphertext, from: partnerUserID)

            if let payload = try? jsonDecoder.decode(LocationPayload.self, from: decrypted) {
                let now = Date().timeIntervalSince1970
                if now - payload.sentAt > maxPartnerLocationAge {
                    notifyOnMain {
                        self.onDistanceUpdated?(nil)
                    }
                    return
                }

                locationService.updatePartnerLocation(latitude: payload.latitude, longitude: payload.longitude)
                return
            }

            notifyOnMain {
                self.onDistanceUpdated?(nil)
            }
        } catch {
            guard !isRecoverablePartnerPayloadError(error) else {
                attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)
                notifyOnMain {
                    self.onDistanceUpdated?(nil)
                }
                return
            }
            emitError(error)
        }
    }

    func startLocationSharingIfNeeded() {
        guard isSecureChannelReady else {
            stopLocationSharing(resetDistance: true)
            return
        }

        locationService.requestPermissionAndStart()
    }

    func stopLocationSharing(resetDistance: Bool) {
        locationService.stop()
        locationService.clearPartnerLocation()
        lastUploadedLocation = nil
        lastLocationUploadDate = nil

        guard resetDistance else { return }
        notifyOnMain {
            self.onDistanceUpdated?(nil)
        }
    }

    func handleOwnLocationUpdate(_ location: CLLocation) {
        didReportLocationPermissionDenied = false
        guard isSecureChannelReady,
              let currentUserID,
              let partnerUserID else {
            return
        }

        guard shouldUpload(location: location) else { return }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sentAt: Date().timeIntervalSince1970,
            isSimulated: {
                if #available(iOS 15.0, *) {
                    return location.sourceInformation?.isSimulatedBySoftware
                }
                return nil
            }()
        )

        do {
            let plainData = try jsonEncoder.encode(payload)
            let ciphertext = try encryption.encrypt(plainData, for: partnerUserID)
            firebase.updateLocationCiphertext(uid: currentUserID, ciphertext: ciphertext) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.emitError(error)
                }
            }
            lastUploadedLocation = location
            lastLocationUploadDate = Date()
        } catch {
            emitError(error)
        }
    }

    func shouldUpload(location: CLLocation) -> Bool {
        guard let lastLocation = lastUploadedLocation,
              let lastDate = lastLocationUploadDate else {
            return true
        }

        let movedDistance = location.distance(from: lastLocation)
        if movedDistance >= minimumLocationUploadDistanceMeters {
            return true
        }

        let elapsed = Date().timeIntervalSince(lastDate)
        return elapsed >= minimumLocationUploadInterval
    }

    func publishDistance(_ kilometers: Double) {
        guard kilometers.isFinite, kilometers >= 0 else { return }

        let formatted = formatDistance(kilometers: kilometers)
        persistWidgetDistance(formatted)
        notifyOnMain {
            self.onDistanceUpdated?(formatted)
        }
    }

    func formatDistance(kilometers: Double) -> String {
        if kilometers < 10 {
            cachedNumberFormatter.maximumFractionDigits = 2
        } else if kilometers < 100 {
            cachedNumberFormatter.maximumFractionDigits = 1
        } else {
            cachedNumberFormatter.maximumFractionDigits = 0
        }

        let measurement = Measurement(value: kilometers, unit: UnitLength.kilometers)
        cachedMeasurementFormatter.numberFormatter = cachedNumberFormatter
        return cachedMeasurementFormatter.string(from: measurement)
    }
}
