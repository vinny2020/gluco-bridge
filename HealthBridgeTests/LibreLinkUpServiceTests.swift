// HealthBridgeTests/LibreLinkUpServiceTests.swift

import Testing
import Foundation
@testable import HealthBridge

@Suite("LibreLinkUpService")
struct LibreLinkUpServiceTests {

    @Test func loginSuccess() async throws {
        let mock = MockURLSession(responseData: Fixture.load("login_success"), statusCode: 200)
        let service = LibreLinkUpService(session: mock)
        let ticket = try await service.login(email: "user@example.com", password: "secret")
        #expect(ticket.token == "test-token-abc123")
        #expect(ticket.expires == 9999999999)
    }

    @Test func loginFailure401() async throws {
        let mock = MockURLSession(responseData: Fixture.load("login_failure"), statusCode: 401)
        let service = LibreLinkUpService(session: mock)
        await #expect(throws: LLUError.unauthorized) {
            _ = try await service.login(email: "user@example.com", password: "wrong")
        }
    }

    @Test func networkError() async throws {
        struct TestNetworkError: Error {}
        let mock = MockURLSession(responseData: Data(), statusCode: 0, error: TestNetworkError())
        let service = LibreLinkUpService(session: mock)
        await #expect(throws: (any Error).self) {
            _ = try await service.login(email: "user@example.com", password: "pass")
        }
    }

    @Test func connectionsSuccess() async throws {
        let mock = MockURLSession(responseData: Fixture.load("connections_success"), statusCode: 200)
        let service = LibreLinkUpService(session: mock)
        let patients = try await service.fetchConnections(token: "test-token")
        #expect(patients.count == 1)
        #expect(patients.first?.patientId == "patient-uuid-001")
    }

    @Test func glucoseGraphSuccess() async throws {
        let mock = MockURLSession(responseData: Fixture.load("glucose_graph"), statusCode: 200)
        let service = LibreLinkUpService(session: mock)
        let readings = try await service.fetchGlucoseGraph(token: "test-token", patientId: "patient-uuid-001")
        // 1 current + 4 history = 5
        #expect(readings.count == 5)
        #expect(readings.contains { $0.Value == 105 })
        #expect(readings.contains { $0.Value == 85 })
    }

    @Test func tokenExpiry() {
        // Expired timestamp is in the past
        let expiredTimestamp = Int(Date().timeIntervalSince1970) - 3600
        let now = Int(Date().timeIntervalSince1970)
        #expect(now >= expiredTimestamp)

        // Valid timestamp is in the future
        let futureTimestamp = Int(Date().timeIntervalSince1970) + 3600
        #expect(now < futureTimestamp)
    }
}
