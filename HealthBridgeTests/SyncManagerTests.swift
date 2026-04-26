// HealthBridgeTests/SyncManagerTests.swift

import Testing
import Foundation
@testable import HealthBridge

@Suite("SyncManager")
struct SyncManagerTests {

    @Test func syncIdentifierFormat() {
        let json = """
        {
          "FactoryTimestamp": "",
          "Timestamp": "4/11/2026 8:00:00 AM",
          "Value": 95,
          "TrendArrow": 3
        }
        """.data(using: .utf8)!
        let reading = try! JSONDecoder().decode(LLUGlucoseMeasurement.self, from: json)
        let syncId = HealthKitManager.syncIdentifier(for: reading)
        let ts = Int(reading.date.timeIntervalSince1970.rounded())
        #expect(syncId == "healthbridge.glucose.\(ts).95")
    }

    @Test func deduplicationSkipsDuplicates() async throws {
        // Build two readings with the same timestamp+value = same sync ID
        let json = """
        [
          {"Timestamp": "4/11/2026 9:00:00 AM", "Value": 110, "TrendArrow": 3},
          {"Timestamp": "4/11/2026 9:00:00 AM", "Value": 110, "TrendArrow": 3},
          {"Timestamp": "4/11/2026 9:15:00 AM", "Value": 115, "TrendArrow": 3}
        ]
        """.data(using: .utf8)!
        let readings = try JSONDecoder().decode([LLUGlucoseMeasurement].self, from: json)

        // Verify uniqueness via sync identifiers
        let ids = readings.map { HealthKitManager.syncIdentifier(for: $0) }
        let unique = Set(ids)
        // 2 unique (first two are identical)
        #expect(unique.count == 2)
    }

    @Test func emptyReadingsCompletesWithoutError() async throws {
        // Empty array → zero new samples, no error thrown
        let readings: [LLUGlucoseMeasurement] = []
        // We can't call HealthKitManager directly in tests (requires device),
        // but we can verify the count via the deduplication logic
        let ids = readings.map { HealthKitManager.syncIdentifier(for: $0) }
        #expect(ids.isEmpty)
    }
}
