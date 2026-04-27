// Views/ConnectView.swift

import SwiftUI
import UIKit

struct ConnectView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var healthKit: HealthKitManager

    @State private var email = ""
    @State private var password = ""
    @State private var selectedSensorId: String = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var patientName: String?

    private var sensors: [SensorDefinition] {
        SensorRegistry.shared.sensors
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sensor") {
                    if sensors.isEmpty {
                        Text("No sensors available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Sensor Type", selection: $selectedSensorId) {
                            ForEach(sensors) { sensor in
                                Text(sensor.name).tag(sensor.id)
                            }
                        }
                    }
                }

                Section("LibreLinkUp Account") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let error = errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = error
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy error message")
                        }
                    }
                }

                Section {
                    Button(action: connect) {
                        if isConnecting {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting…")
                            }
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isConnecting || email.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("HealthBridge")
        }
        .onAppear {
            // Restore the previously selected sensor if it's still in the registry,
            // otherwise default to the first (newest) sensor in sensors.json.
            if let saved = UserDefaults.standard.string(forKey: "selectedSensorId"),
               sensors.contains(where: { $0.id == saved }) {
                selectedSensorId = saved
            } else if let first = sensors.first {
                selectedSensorId = first.id
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        Task {
            defer { isConnecting = false }

            do {
                let service = LibreLinkUpService()
                let ticket = try await service.login(email: email, password: password)

                KeychainHelper.save(key: "llu.email", value: email)
                KeychainHelper.save(key: "llu.password", value: password)
                KeychainHelper.save(key: "llu.authToken", value: ticket.token)
                KeychainHelper.save(key: "llu.tokenExpires", value: String(ticket.expires))
                if let region = await service.currentRegion {
                    KeychainHelper.save(key: "llu.region", value: region)
                }
                if let accountId = await service.currentAccountId {
                    KeychainHelper.save(key: "llu.accountId", value: accountId)
                }
                UserDefaults.standard.set(selectedSensorId, forKey: "selectedSensorId")

                let patients = try await service.fetchConnections(token: ticket.token)
                guard let patient = patients.first else {
                    errorMessage = "No connected patients found in your LibreLinkUp account."
                    return
                }

                KeychainHelper.save(key: "llu.patientId", value: patient.patientId)
                patientName = patient.displayName
                UserDefaults.standard.set(patient.displayName, forKey: "patientDisplayName")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "sensorStartDate")

                try await healthKit.requestAuthorization()

                await syncManager.fullHistorySync()

            } catch {
                errorMessage = error.localizedDescription
                // Only fully reset credentials on a real auth rejection. For network or
                // decoding errors the saved token is still likely valid, so keep it
                // (and the typed email/password) so the user can retry without re-entry.
                if case LLUError.unauthorized = error {
                    KeychainHelper.clearAll()
                }
            }
        }
    }
}
