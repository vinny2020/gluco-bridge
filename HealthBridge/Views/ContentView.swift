// Views/ContentView.swift

import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var healthKit: HealthKitManager

    private var patientName: String {
        guard let id = KeychainHelper.load(key: "llu.patientId") else { return "Unknown" }
        return id  // We show the patient name stored separately if available
    }

    private var sensorName: String {
        let id = UserDefaults.standard.string(forKey: "selectedSensorId") ?? ""
        return SensorRegistry.shared.sensor(for: id)?.name ?? "Unknown Sensor"
    }

    private var sensorDurationDays: Int {
        let id = UserDefaults.standard.string(forKey: "selectedSensorId") ?? ""
        return SensorRegistry.shared.sensor(for: id)?.durationDays ?? 14
    }

    private var nextSensorChangeDate: Date? {
        guard let dateStr = UserDefaults.standard.string(forKey: "sensorStartDate"),
              let ts = Double(dateStr) else { return nil }
        let start = Date(timeIntervalSince1970: ts)
        return start.addingTimeInterval(Double(sensorDurationDays) * 86400)
    }

    private var lastSyncText: String {
        guard let date = syncManager.lastSyncDate else { return "Never" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) minutes ago" }
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(syncManager.syncError == nil ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text("Connected")
                                .fontWeight(.semibold)
                        }
                        Text(storedPatientName)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Text(sensorName)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }

                Section("Sync Status") {
                    LabeledContent("Last sync", value: lastSyncText)
                    LabeledContent("Readings written today", value: "\(syncManager.lastSyncCount)")
                    LabeledContent("Total synced", value: "\(syncManager.totalSynced)")

                    if let error = syncManager.syncError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button {
                        Task { await syncManager.sync() }
                    } label: {
                        HStack {
                            if syncManager.isSyncing {
                                ProgressView().controlSize(.small)
                            }
                            Text(syncManager.isSyncing ? "Syncing…" : "Sync Now")
                        }
                    }
                    .disabled(syncManager.isSyncing)
                }

                Section("Status") {
                    HStack {
                        Text("Background sync")
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("Active")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Button {
                        if !healthKit.isAuthorized() {
                            if let url = URL(string: "x-apple-health://") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Apple Health")
                            Spacer()
                            Circle()
                                .fill(healthKit.isAuthorized() ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(healthKit.isAuthorized() ? "Authorized" : "Not authorized")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                if let changeDate = nextSensorChangeDate {
                    Section {
                        LabeledContent("Next sensor change", value: sensorChangeSummary(changeDate))
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        syncManager.disconnect()
                    }
                }
            }
            .navigationTitle("HealthBridge")
            .onAppear {
                healthKit.refreshAuthorizationStatus()
            }
        }
    }

    private var storedPatientName: String {
        // Try to get a display name stored during connect
        UserDefaults.standard.string(forKey: "patientDisplayName") ?? "Connected Patient"
    }

    private func sensorChangeSummary(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if days < 0 {
            return "\(formatted) (overdue)"
        }
        return "\(formatted) (\(days) day\(days == 1 ? "" : "s"))"
    }
}
