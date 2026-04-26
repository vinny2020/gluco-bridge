// HealthBridgeTests/LibreLinkUpModelsTests.swift

import Testing
import Foundation
@testable import HealthBridge

@Suite("LibreLinkUpModels")
struct LibreLinkUpModelsTests {

    @Test func loginResponseDecoding() throws {
        let data = Fixture.load("login_success")
        let decoded = try JSONDecoder().decode(LLULoginResponse.self, from: data)
        #expect(decoded.data?.authTicket.token == "test-token-abc123")
        #expect(decoded.data?.authTicket.expires == 9999999999)
    }

    @Test func glucoseDecoding() throws {
        let data = Fixture.load("glucose_graph")
        let decoded = try JSONDecoder().decode(LLUGraphResponse.self, from: data)
        let current = decoded.data?.connection?.glucoseMeasurement
        #expect(current?.Value == 105)
        #expect(current?.Timestamp == "4/11/2026 8:00:00 AM")
    }

    @Test func connectionsDecoding() throws {
        let data = Fixture.load("connections_success")
        let decoded = try JSONDecoder().decode(LLUConnectionsResponse.self, from: data)
        #expect(decoded.data?.first?.patientId == "patient-uuid-001")
        #expect(decoded.data?.first?.firstName == "Vincent")
    }

    @Test func malformedJSONDoesNotCrash() {
        let bad = Data("{ not valid json }".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(LLULoginResponse.self, from: bad)
        }
    }

    @Test func glucoseSyncIdentifierFormat() {
        // Build a fake measurement and verify sync ID format
        let json = """
        {
          "FactoryTimestamp": "1/1/2026 12:00:00 AM",
          "Timestamp": "1/1/2026 12:00:00 AM",
          "Value": 110,
          "TrendArrow": 3
        }
        """.data(using: .utf8)!
        let measurement = try! JSONDecoder().decode(LLUGlucoseMeasurement.self, from: json)
        let syncId = HealthKitManager.syncIdentifier(for: measurement)
        #expect(syncId.hasPrefix("healthbridge.glucose."))
        #expect(syncId.hasSuffix(".110"))
    }
}
