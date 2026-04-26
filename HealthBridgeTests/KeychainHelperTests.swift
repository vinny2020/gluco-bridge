// HealthBridgeTests/KeychainHelperTests.swift

import Testing
import Foundation
@testable import HealthBridge

@Suite("KeychainHelper")
struct KeychainHelperTests {
    private let testKey = "test.keychain.key.\(UUID().uuidString)"

    @Test func saveAndLoad() {
        KeychainHelper.save(key: testKey, value: "hello")
        let loaded = KeychainHelper.load(key: testKey)
        #expect(loaded == "hello")
        KeychainHelper.delete(key: testKey)
    }

    @Test func delete() {
        KeychainHelper.save(key: testKey, value: "to-be-deleted")
        KeychainHelper.delete(key: testKey)
        #expect(KeychainHelper.load(key: testKey) == nil)
    }

    @Test func overwrite() {
        KeychainHelper.save(key: testKey, value: "first")
        KeychainHelper.save(key: testKey, value: "second")
        let loaded = KeychainHelper.load(key: testKey)
        #expect(loaded == "second")
        KeychainHelper.delete(key: testKey)
    }

    @Test func loadNonExistent() {
        let result = KeychainHelper.load(key: "nonexistent.key.\(UUID().uuidString)")
        #expect(result == nil)
    }
}
