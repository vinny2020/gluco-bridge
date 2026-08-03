// Background/BackgroundTaskManager.swift

import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let taskIdentifier = "com.xaymaca.healthbridge.sync"
    static let backfillIdentifier = "com.xaymaca.healthbridge.backfill"

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

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backfillIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackfillTask(processingTask)
        }
    }

    // MARK: - Schedule

    static func scheduleNextSync() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Issue #1 Layer 4: nightly full-history pull while the phone charges,
    /// healing any day where every other trigger layer failed.
    static func scheduleNightlyBackfill() {
        let request = BGProcessingTaskRequest(identifier: backfillIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        request.earliestBeginDate = nextBackfillDate()
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Next 2 AM local time — overlaps typical overnight charging.
    private static func nextBackfillDate() -> Date {
        Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 2),
            matchingPolicy: .nextTime
        ) ?? Date(timeIntervalSinceNow: 8 * 3600)
    }

    // MARK: - Handle

    static func handleSyncTask(_ task: BGAppRefreshTask) {
        scheduleNextSync()
        run(task) { await $0.sync() }
    }

    static func handleBackfillTask(_ task: BGProcessingTask) {
        scheduleNightlyBackfill()
        run(task) { await $0.fullHistorySync() }
    }

    private static func run(
        _ task: BGTask,
        _ operation: @escaping @Sendable @MainActor (SyncManager) async -> Void
    ) {
        // BGTask is not Sendable; use nonisolated(unsafe) to cross actor boundary.
        // BGTaskScheduler serializes handler + expiration callbacks, and the
        // completion guard below ensures setTaskCompleted runs exactly once.
        nonisolated(unsafe) let bgTask = task
        let completion = TaskCompletionGuard()

        let work = Task { @MainActor in
            let syncManager = SyncManager()
            await operation(syncManager)
            completion.complete { bgTask.setTaskCompleted(success: syncManager.syncError == nil) }
        }

        task.expirationHandler = {
            work.cancel()
            completion.complete { bgTask.setTaskCompleted(success: false) }
        }
    }

    // MARK: - Status

    /// True if a background refresh request is waiting with iOS. Feeds the
    /// (no longer hardcoded) "Background sync" indicator in ContentView.
    static func hasPendingSyncRequest() async -> Bool {
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        return pending.contains { $0.identifier == taskIdentifier }
    }
}

/// Ensures a BGTask is completed exactly once even when the sync task and the
/// expiration handler race.
private final class TaskCompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func complete(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        body()
    }
}
