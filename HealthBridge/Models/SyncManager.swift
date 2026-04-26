// Models/SyncManager.swift

import Foundation

@MainActor
class SyncManager: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var lastSyncCount: Int = 0
    @Published var syncError: String?
    @Published var isSyncing: Bool = false
    @Published var totalSynced: Int = 0

    private let lluService: LibreLinkUpService
    private let healthKit: HealthKitManager
    private let totalSyncedKey = "healthbridge.totalSynced"

    init(lluService: LibreLinkUpService = LibreLinkUpService(),
         healthKit: HealthKitManager = HealthKitManager()) {
        self.lluService = lluService
        self.healthKit = healthKit
        self.totalSynced = UserDefaults.standard.integer(forKey: totalSyncedKey)
    }

    // MARK: - Incremental sync

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let token = try await validToken()
            guard let patientId = KeychainHelper.load(key: "llu.patientId") else {
                syncError = "No patient selected. Please reconnect."
                return
            }

            let readings = try await lluService.fetchGlucoseGraph(token: token, patientId: patientId)
            let written = try await healthKit.saveGlucoseSamples(readings)

            lastSyncDate = Date()
            lastSyncCount = written
            totalSynced += written
            UserDefaults.standard.set(totalSynced, forKey: totalSyncedKey)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Full history sync (first run, last 14 days)

    func fullHistorySync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let token = try await validToken()
            guard let patientId = KeychainHelper.load(key: "llu.patientId") else {
                syncError = "No patient selected. Please reconnect."
                return
            }

            // LibreLinkUp graph endpoint returns ~14 days of data in one call
            let readings = try await lluService.fetchGlucoseGraph(token: token, patientId: patientId)
            let written = try await healthKit.saveGlucoseSamples(readings)

            lastSyncDate = Date()
            lastSyncCount = written
            totalSynced += written
            UserDefaults.standard.set(totalSynced, forKey: totalSyncedKey)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Token management

    private func validToken() async throws -> String {
        if let token = KeychainHelper.load(key: "llu.authToken"),
           !token.isEmpty,
           !isTokenExpired() {
            return token
        }

        // Re-login
        guard let email = KeychainHelper.load(key: "llu.email"),
              let password = KeychainHelper.load(key: "llu.password") else {
            throw LLUError.unauthorized
        }

        let ticket = try await lluService.login(email: email, password: password)
        KeychainHelper.save(key: "llu.authToken", value: ticket.token)
        KeychainHelper.save(key: "llu.tokenExpires", value: String(ticket.expires))
        return ticket.token
    }

    private func isTokenExpired() -> Bool {
        guard let expiresStr = KeychainHelper.load(key: "llu.tokenExpires"),
              let expires = Int(expiresStr) else {
            return true
        }
        let now = Int(Date().timeIntervalSince1970)
        return now >= expires
    }

    // MARK: - Disconnect

    func disconnect() {
        KeychainHelper.clearAll()
        lastSyncDate = nil
        lastSyncCount = 0
        syncError = nil
        totalSynced = 0
        UserDefaults.standard.removeObject(forKey: totalSyncedKey)
    }
}
