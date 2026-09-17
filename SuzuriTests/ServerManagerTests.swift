import XCTest
@testable import Suzuri

final class ServerManagerTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SuzuriServerManagerTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func testMirrorAPIBaseURLs() {
        XCTAssertEqual(ServerManager.Mirror.telegraph.apiBase, "https://api.telegra.ph")
        XCTAssertEqual(ServerManager.Mirror.graph.apiBase, "https://api.graph.org")
        XCTAssertEqual(ServerManager.Mirror.legraph.apiBase, "https://api.legra.ph")
    }

    func testDefaultMirrorIsTelegraph() {
        let defaults = makeDefaults()
        XCTAssertEqual(ServerManager(defaults: defaults).current, .telegraph)
    }

    func testCurrentMirrorPersists() {
        let defaults = makeDefaults()
        let manager = ServerManager(defaults: defaults)
        manager.current = .graph

        XCTAssertEqual(ServerManager(defaults: defaults).current, .graph)
    }

    func testCustomMirrorPersistsAndSuppliesAPIBase() {
        let defaults = makeDefaults()
        let manager = ServerManager(defaults: defaults)
        manager.customAPIBase = "https://api.example.test"
        manager.current = .custom

        let restored = ServerManager(defaults: defaults)
        XCTAssertEqual(restored.current, .custom)
        XCTAssertEqual(restored.apiBase, "https://api.example.test")
        XCTAssertEqual(restored.current.apiBase(using: defaults), "https://api.example.test")
        XCTAssertEqual(restored.apiURL?.host, "api.example.test")
    }

    func testResetReturnsToTelegraphAndRemovesCustomValue() {
        let defaults = makeDefaults()
        let manager = ServerManager(defaults: defaults)
        manager.customAPIBase = "https://api.example.test"
        manager.current = .custom

        manager.reset()

        XCTAssertEqual(manager.current, .telegraph)
        XCTAssertEqual(manager.apiBase, "https://api.telegra.ph")
        XCTAssertNil(defaults.string(forKey: ServerManager.customAPIKey))
    }
}
