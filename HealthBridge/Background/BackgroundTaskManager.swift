// Background/BackgroundTaskManager.swift

import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let taskIdentifier = "com.xaymaca.healthbridge.sync"

    // MARK: - Registration

    static func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleSyncTask(refreshTask)
        }
    }

    // MARK: - Schedule

    static func scheduleNextSync() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handle

    static func handleSyncTask(_ task: BGAppRefreshTask) {
        scheduleNextSync()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // BGTask is not Sendable; use nonisolated(unsafe) to cross actor boundary.
        // BGTaskScheduler calls this handler on the main queue so concurrent access is not a concern.
        nonisolated(unsafe) let bgTask = task

        Task { @MainActor in
            let syncManager = SyncManager()
            await syncManager.sync()
            bgTask.setTaskCompleted(success: syncManager.syncError == nil)
        }
    }
}
