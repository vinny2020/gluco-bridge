// Models/SensorRegistry.swift

import Foundation

struct SensorDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let durationDays: Int
}

@MainActor
class SensorRegistry {
    static let shared = SensorRegistry()
    private(set) var sensors: [SensorDefinition] = []

    private init() {}

    func load() {
        guard let url = Bundle.main.url(forResource: "sensors", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            sensors = try JSONDecoder().decode([SensorDefinition].self, from: data)
        } catch {
            // Silently fail — sensors array remains empty
        }
    }

    func refresh(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([SensorDefinition].self, from: data)
            sensors = decoded
        } catch {
            // Keep existing sensors on failure
        }
    }

    func sensor(for id: String) -> SensorDefinition? {
        sensors.first { $0.id == id }
    }
}
