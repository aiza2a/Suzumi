import XCTest
@testable import Suzuri

@MainActor
final class TokenStoreTests: XCTestCase {
    func testOriginUsesSchemeHostAndNonDefaultPort() {
        XCTAssertEqual(
            TokenStore.origin(for: "HTTPS://API.Example.com/path?route=1"),
            "https://api.example.com"
        )
        XCTAssertEqual(
            TokenStore.origin(for: "https://api.example.com:8443/v1"),
            "https://api.example.com:8443"
        )
    }

    func testDifferentOriginsUseDifferentScopedAccounts() {
        let telegraph = TokenStore.scopedAccount(
            .accessToken,
            origin: TokenStore.origin(for: "https://api.telegra.ph")
        )
        let graph = TokenStore.scopedAccount(
            .accessToken,
            origin: TokenStore.origin(for: "https://api.graph.org")
        )

        XCTAssertNotEqual(telegraph, graph)
        XCTAssertTrue(telegraph.hasPrefix("access_token_"))
    }

    func testLegacyAccessTokenMigratesToDefaultOrigin() throws {
        let service = "SuzuriTokenMigration-\(UUID().uuidString)"
        let store = TokenStore(service: service)
        let defaultOrigin = TokenStore.origin(for: "https://api.telegra.ph")
        defer {
            store.delete(TokenStore.Key.accessToken.rawValue)
            store.delete(.accessToken, origin: defaultOrigin)
        }

        try store.saveString("legacy-token", for: TokenStore.Key.accessToken.rawValue)
        let controller = SessionController(
            serverManager: ServerManager(),
            tokenStore: store
        )

        XCTAssertEqual(controller.accessToken, "legacy-token")
        XCTAssertNil(store.loadString(TokenStore.Key.accessToken.rawValue))
        XCTAssertEqual(store.loadString(.accessToken, origin: defaultOrigin), "legacy-token")
    }

    func testFingerprintIsStableAndDoesNotContainOriginalValue() {
        let value = "https://api.telegra.ph|token"
        let fingerprint = TokenStore.fingerprint(value)

        XCTAssertEqual(fingerprint, TokenStore.fingerprint(value))
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertFalse(fingerprint.contains("telegra"))
    }
}
