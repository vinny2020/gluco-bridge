// HealthBridgeApp.swift

import SwiftUI

@main
struct HealthBridgeApp: App {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var healthKit = HealthKitManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SensorRegistry.shared.load()
        BackgroundTaskManager.registerTasks()
        // Issue #1 Layer 1: nothing ever submitted the FIRST BGAppRefreshTask
        // request (scheduleNextSync was only called from inside the handler).
        // Submit one at launch, and again whenever we go to background below.
        BackgroundTaskManager.scheduleNextSync()
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
            default:
                break
            }
        }
    }
}
