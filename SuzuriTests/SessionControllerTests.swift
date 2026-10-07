import XCTest
@testable import Suzuri

private final class AccountURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response = #"{"ok":true,"result":{"short_name":"existing","author_name":"Remote","author_url":"https://remote.example"}}"#
    nonisolated(unsafe) static var onStart: ((AccountURLProtocol) -> Void)?
    nonisolated(unsafe) static var pending: AccountURLProtocol?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let onStart = Self.onStart { onStart(self) } else { finish() }
    }
    func finish() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SessionControllerTests: XCTestCase {
    private func fixture() -> (SessionController, TokenStore, ServerManager) {
        let id = UUID().uuidString
        let store = TokenStore(service: "SuzuriSessionTests-\(id)")
        let defaults = UserDefaults(suiteName: "SuzuriSessionTests-\(id)")!
        let manager = ServerManager(defaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountURLProtocol.self]
        AccountURLProtocol.onStart = nil
        AccountURLProtocol.pending = nil
        AccountURLProtocol.response = #"{"ok":true,"result":{"short_name":"existing","author_name":"Remote","author_url":"https://remote.example"}}"#
        return (SessionController(serverManager: manager, tokenStore: store,
                                  session: URLSession(configuration: configuration)), store, manager)
    }

    func testInvalidImportKeepsExistingTokenAndProfile() async throws {
        let (controller, store, _) = fixture()
        try await controller.importAccessToken("previous-token")
        AccountURLProtocol.response = #"{"ok":false,"error":"ACCESS_TOKEN_INVALID"}"#
        do {
            try await controller.importAccessToken("invalid-token")
            XCTFail("Invalid remote token must fail")
        } catch {}
        XCTAssertEqual(controller.accessToken, "previous-token")
        XCTAssertEqual(store.loadString(.accessToken, origin: controller.currentOrigin), "previous-token")
        store.delete(.accessToken, origin: controller.currentOrigin)
        store.delete(.shortName, origin: controller.currentOrigin)
    }

    func testLoadPreservesExplicitLocalAuthorIncludingBlankURL() async throws {
        let (controller, store, _) = fixture()
        try controller.updateAuthorProfile(name: "Local", url: "")
        try await controller.importAccessToken("existing-token")
        XCTAssertEqual(controller.authorName, "Local")
        XCTAssertNil(controller.authorURL)
        store.delete(SessionController.authorNameKey)
        store.delete(SessionController.authorURLKey)
        store.delete(.accessToken, origin: controller.currentOrigin)
        store.delete(.shortName, origin: controller.currentOrigin)
    }

    func testLateRevokeResponseCannotClearAnotherMirrorsToken() async throws {
        let (controller, store, manager) = fixture()
        try await controller.importAccessToken("telegraph-token")
        let originalOrigin = controller.currentOrigin
        let graphOrigin = "https://api.graph.org"
        try store.saveString("graph-token", for: .accessToken, origin: graphOrigin)
        let started = expectation(description: "Revoke request started")
        AccountURLProtocol.onStart = { request in
            AccountURLProtocol.pending = request
            started.fulfill()
        }
        let revoke = Task { try await controller.revokeAccess() }
        await fulfillment(of: [started], timeout: 2)
        manager.current = .graph
        controller.synchronizeOrigin()
        AccountURLProtocol.pending?.finish()
        try await revoke.value
        XCTAssertEqual(controller.accessToken, "graph-token")
        XCTAssertEqual(store.loadString(.accessToken, origin: graphOrigin), "graph-token")
        AccountURLProtocol.onStart = nil
        store.delete(.accessToken, origin: originalOrigin)
        store.delete(.shortName, origin: originalOrigin)
        store.delete(.accessToken, origin: graphOrigin)
    }

    func testLateImportCannotReplaceNewlySelectedOrigin() async throws {
        let (controller, store, manager) = fixture()
        let started = expectation(description: "Import validation started")
        AccountURLProtocol.onStart = { request in AccountURLProtocol.pending = request; started.fulfill() }
        let importing = Task { try await controller.importAccessToken("old-origin-token") }
        await fulfillment(of: [started], timeout: 2)
        manager.current = .graph
        controller.synchronizeOrigin()
        AccountURLProtocol.pending?.finish()
        do {
            try await importing.value
            XCTFail("Stale validation must fail")
        } catch {}
        XCTAssertNil(controller.accessToken)
        XCTAssertNil(store.loadString(.accessToken, origin: "https://api.telegra.ph"))
        AccountURLProtocol.onStart = nil
    }

    func testLateRevokeCannotClearReplacementTokenOnSameOrigin() async throws {
        let (controller, store, _) = fixture()
        try await controller.importAccessToken("first-token")
        let started = expectation(description: "Revoke suspended")
        AccountURLProtocol.onStart = { request in
            if request.request.url?.lastPathComponent == "revokeAccessToken" {
                AccountURLProtocol.pending = request
                started.fulfill()
            } else {
                request.finish()
            }
        }
        let revoke = Task { try await controller.revokeAccess() }
        await fulfillment(of: [started], timeout: 2)
        try await controller.importAccessToken("replacement-token")
        AccountURLProtocol.pending?.finish()
        try await revoke.value
        XCTAssertEqual(controller.accessToken, "replacement-token")
        XCTAssertEqual(store.loadString(.accessToken, origin: controller.currentOrigin), "replacement-token")
        AccountURLProtocol.onStart = nil
        store.delete(.accessToken, origin: controller.currentOrigin)
        store.delete(.shortName, origin: controller.currentOrigin)
    }
}
