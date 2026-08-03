// HealthBridgeApp.swift

import SwiftUI

@main
struct HealthBridgeApp: App {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var healthKit = HealthKitManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Simulator testing hook: seed fake credentials so ContentView and the
        // sync triggers can be exercised without a real LLU account. Syncs will
        // fail at the LLU API (fake token) — that's expected; this exists to
        // verify the trigger layers fire, not to fetch data.
        if ProcessInfo.processInfo.arguments.contains("-seedFakeAuth") {
            KeychainHelper.save(key: "llu.email", value: "sim@example.com")
            KeychainHelper.save(key: "llu.password", value: "not-a-real-password")
            KeychainHelper.save(key: "llu.authToken", value: "sim-fake-token")
            KeychainHelper.save(key: "llu.tokenExpires",
                                value: String(Int(Date().timeIntervalSince1970) + 3600))
            KeychainHelper.save(key: "llu.patientId", value: "sim-patient")
            UserDefaults.standard.set("libre3plus", forKey: "selectedSensorId")
            UserDefaults.standard.set("Simulator Test", forKey: "patientDisplayName")
        }
        #endif

        SensorRegistry.shared.load()
        BackgroundTaskManager.registerTasks()
        // Issue #1 Layer 1: nothing ever submitted the FIRST BGAppRefreshTask
        // request (scheduleNextSync was only called from inside the handler).
        // Submit one at launch, and again whenever we go to background below.
        BackgroundTaskManager.scheduleNextSync()
        BackgroundTaskManager.scheduleNightlyBackfill()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if KeychainHelper.load(key: "llu.authToken") != nil {
                    ContentView()
                } else {
                    ConnectView()
                }
            }
            .environmentObject(syncManager)
            .environmentObject(healthKit)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Issue #1 Layer 2: opening the app IS the sync.
                // Debounced so rapid app switches don't hammer LLU.
                guard KeychainHelper.load(key: "llu.authToken") != nil else { return }
                Task { await syncManager.syncIfStale() }
            case .background:
                // Apple's recommended point to submit the next BG refresh request.
                BackgroundTaskManager.scheduleNextSync()
                BackgroundTaskManager.scheduleNightlyBackfill()
            default:
                break
            }
        }
    }
}
