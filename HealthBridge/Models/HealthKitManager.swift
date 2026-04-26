// Models/HealthKitManager.swift

import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined

    private let healthStore = HKHealthStore()

    private var glucoseType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .bloodGlucose)!
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [glucoseType], read: []) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        authorizationStatus = healthStore.authorizationStatus(for: glucoseType)
    }

    func isAuthorized() -> Bool {
        healthStore.authorizationStatus(for: glucoseType) == .sharingAuthorized
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = healthStore.authorizationStatus(for: glucoseType)
    }

    // MARK: - Write glucose samples

    /// Returns the count of newly written samples (duplicates are skipped).
    func saveGlucoseSamples(_ readings: [LLUGlucoseMeasurement]) async throws -> Int {
        guard !readings.isEmpty else { return 0 }

        let dates = readings.map(\.date)
        let from = dates.min() ?? .distantPast
        let to   = dates.max() ?? .distantFuture

        let existing = try await existingSyncIdentifiers(from: from, to: to)

        let newSamples: [HKQuantitySample] = readings.compactMap { reading in
            let syncId = syncIdentifier(for: reading)
            guard !existing.contains(syncId) else { return nil }

            let quantity = HKQuantity(unit: HKUnit(from: "mg/dL"), doubleValue: reading.mgdl)
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: syncId,
                HKMetadataKeySyncVersion: 1
            ]
            return HKQuantitySample(
                type: glucoseType,
                quantity: quantity,
                start: reading.date,
                end: reading.date,
                metadata: metadata
            )
        }

        guard !newSamples.isEmpty else { return 0 }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.save(newSamples) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }

        return newSamples.count
    }

    // MARK: - Sync identifier

    nonisolated static func syncIdentifier(for reading: LLUGlucoseMeasurement) -> String {
        let ts = Int(reading.date.timeIntervalSince1970.rounded())
        return "healthbridge.glucose.\(ts).\(reading.Value)"
    }

    private nonisolated func syncIdentifier(for reading: LLUGlucoseMeasurement) -> String {
        Self.syncIdentifier(for: reading)
    }

    // MARK: - Deduplication query

    private func existingSyncIdentifiers(from: Date, to: Date) async throws -> Set<String> {
        let start = from.addingTimeInterval(-5 * 60)
        let end   = to.addingTimeInterval(5 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let ids = Set(
                    (samples ?? []).compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
                )
                cont.resume(returning: ids)
            }
            self.healthStore.execute(query)
        }
    }
}
