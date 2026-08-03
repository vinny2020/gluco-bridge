// Intents/SyncGlucoseIntent.swift
//
// Issue #1 Layer 3: lets Shortcuts run a sync in the background without
// opening the app. Users wire it to a Personal Automation ("when <daily-use
// app> opens → Sync Glucose", notifications off) so the phone is guaranteed
// awake when the sync fires — iOS can't be trusted to run BG tasks on a
// locked phone. Time-of-day automations work too.

import AppIntents

struct SyncGlucoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Glucose"
    static let description = IntentDescription(
        "Pulls the latest readings from LibreLinkUp and writes them to Apple Health. Skips if a sync ran in the last 5 minutes."
    )
    // Runs in the background — the whole point for automations.
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard KeychainHelper.load(key: "llu.authToken") != nil else {
            return .result(dialog: "GlucoBridge isn't connected to LibreLinkUp yet. Open the app to connect.")
        }

        let syncManager = SyncManager()
        let ran = await syncManager.syncIfStale()

        // Dialogs report counts only — never glucose values.
        if !ran {
            return .result(dialog: "Already synced in the last 5 minutes.")
        }
        if let error = syncManager.syncError {
            return .result(dialog: "Sync failed: \(error)")
        }
        let written = syncManager.lastSyncCount
        return .result(dialog: "Synced \(written) new reading\(written == 1 ? "" : "s") to Apple Health.")
    }
}

struct HealthBridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncGlucoseIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Sync glucose with \(.applicationName)"
            ],
            shortTitle: "Sync Glucose",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
