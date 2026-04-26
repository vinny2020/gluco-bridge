// HealthBridgeApp.swift

import SwiftUI

@main
struct HealthBridgeApp: App {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var healthKit = HealthKitManager()

    init() {
        SensorRegistry.shared.load()
        BackgroundTaskManager.registerTasks()
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
    }
}
