import XCTest
@testable import Suzuri

/// 用自定义 URLProtocol 拦截 URLSession，注入固定响应。
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var data: Data?
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: URL(string: "https://api.telegra.ph")!,
                          session: session,
                          accessToken: "token-xyz")
    }

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.data = nil
        MockURLProtocol.statusCode = 200
        MockURLProtocol.error = nil
        MockURLProtocol.lastRequest = nil
    }

    /// mock 返回 ok 信封 → 返回 result
    func testReturnsResultOnOk() async throws {
        MockURLProtocol.data = Data(#"{"ok":true,"result":{"short_name":"u1"}}"#.utf8)
        let client = makeClient()
        let acc = try await client.call("createAccount", params: ["short_name": "u1"], as: TelegraphAccount.self)
        XCTAssertEqual(acc.shortName, "u1")
    }

    /// mock 返回 ok=false → 抛 `.api(message:)`
    func testThrowsApiOnOkFalse() async {
        MockURLProtocol.data = Data(#"{"ok":false,"error":"SHORT_NAME_REQUIRED"}"#.utf8)
        let client = makeClient()
        do {
            _ = try await client.call("createAccount", params: [:], as: TelegraphAccount.self)
            XCTFail("应抛 api 错误")
        } catch let err as TelegraphError {
            if case .api(let m) = err {
                XCTAssertEqual(m, "SHORT_NAME_REQUIRED")
            } else {
                XCTFail("应为 .api，实际 \(err)")
            }
        } catch {
            XCTFail("应为 TelegraphError，实际 \(error)")
        }
    }

    /// mock 返回 500 → 抛 `.network`
    func testThrowsNetworkOn500() async {
        MockURLProtocol.statusCode = 500
        MockURLProtocol.data = Data("oops".utf8)
        let client = makeClient()
        do {
            _ = try await client.call("createAccount", params: [:], as: TelegraphAccount.self)
            XCTFail("应抛 network 错误")
        } catch let err as TelegraphError {
            if case .network = err {
                XCTAssertTrue(true)
            } else {
                XCTFail("应为 .network，实际 \(err)")
            }
        } catch {
            XCTFail("应为 TelegraphError，实际 \(error)")
        }
    }

    /// 请求 URL 含 access_token query → 断言 queryItems 存在
    func testAccessTokenInjectedAsQuery() async throws {
        MockURLProtocol.data = Data(#"{"ok":true,"result":{"short_name":"u1"}}"#.utf8)
        let client = makeClient()
        _ = try await client.call(
            "getAccountInfo",
            params: [:],
            as: TelegraphAccount.self,
            httpMethod: "GET"
        )

        let url = try XCTUnwrap(MockURLProtocol.lastRequest?.url)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        XCTAssertTrue(items.contains(where: { $0.name == "access_token" }))
        XCTAssertEqual(comps?.path, "/getAccountInfo")
    }

    /// POST 业务参数进入 form body，token 仍作为 query 参数。
    func testPostParametersUseFormEncodedBody() async throws {
        MockURLProtocol.data = Data(#"{"ok":true,"result":{"short_name":"u1"}}"#.utf8)
        let client = makeClient()
        _ = try await client.call(
            "createAccount",
            params: ["short_name": "a b&c"],
            as: TelegraphAccount.self
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded; charset=utf-8"
        )
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("short_name=a+b%26c"))
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertNil(query?.first(where: { $0.name == "short_name" }))
        XCTAssertEqual(query?.first(where: { $0.name == "access_token" })?.value, "token-xyz")
    }

    /// mock 返回坏 JSON → 抛 `.invalidResponse`
    func testThrowsInvalidResponseOnBadJSON() async {
        MockURLProtocol.data = Data("not-json".utf8)
        let client = makeClient()
        do {
            _ = try await client.call("createAccount", params: [:], as: TelegraphAccount.self)
            XCTFail("应抛 invalidResponse")
        } catch let err as TelegraphError {
            if case .invalidResponse = err {
                XCTAssertTrue(true)
            } else {
                XCTFail("应为 .invalidResponse，实际 \(err)")
            }
        } catch {
            XCTFail("应为 TelegraphError，实际 \(error)")
        }
    }

    /// URLSession 层错误 → 抛 `.network`
    func testThrowsNetworkOnURLError() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        let client = makeClient()
        do {
            _ = try await client.call("createAccount", params: [:], as: TelegraphAccount.self)
            XCTFail("应抛 network 错误")
        } catch let err as TelegraphError {
            if case .network = err {
                XCTAssertTrue(true)
            } else {
                XCTFail("应为 .network，实际 \(err)")
            }
        } catch {
            XCTFail("应为 TelegraphError，实际 \(error)")
        }
    }
}