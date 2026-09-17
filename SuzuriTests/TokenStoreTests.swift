import XCTest
@testable import Suzuri

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

    func testFingerprintIsStableAndDoesNotContainOriginalValue() {
        let value = "https://api.telegra.ph|token"
        let fingerprint = TokenStore.fingerprint(value)

        XCTAssertEqual(fingerprint, TokenStore.fingerprint(value))
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertFalse(fingerprint.contains("telegra"))
    }
}
