// HealthBridgeTests/MockURLSession.swift

import Foundation
@testable import HealthBridge

struct MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var responseData: Data
    var statusCode: Int = 200
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

// MARK: - Fixture loader

enum Fixture {
    private class BundleLocator {}

    /// Load a JSON fixture by name from the test bundle resources.
    static func load(_ name: String) -> Data {
        let bundle = Bundle(for: BundleLocator.self)
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Fixture not found in test bundle: \(name).json")
        }
        return data
    }
}
