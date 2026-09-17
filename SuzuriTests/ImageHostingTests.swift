import Foundation
import XCTest
@testable import Suzuri

/// 用自定义 URLProtocol 注入图床响应并记录请求。
private final class ImageHostingMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var statusCode = 200
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

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor ImageHostingCallCounter {
    private(set) var calls: [String] = []

    func record(_ id: String) {
        calls.append(id)
    }
}

private struct ImageHostingStub: ImageHosting {
    let id: String
    let result: Result<URL, HostError>
    let counter: ImageHostingCallCounter

    var displayName: String { id }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        await counter.record(id)
        return try result.get()
    }
}

final class ImageHostingTests: XCTestCase {
    private let testURL = URL(string: "https://cdn.example/image.jpg")!

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageHostingMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func setUp() {
        super.setUp()
        ImageHostingMockURLProtocol.data = Data()
        ImageHostingMockURLProtocol.statusCode = 200
        ImageHostingMockURLProtocol.error = nil
        ImageHostingMockURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        ImageHostingMockURLProtocol.data = Data()
        ImageHostingMockURLProtocol.statusCode = 200
        ImageHostingMockURLProtocol.error = nil
        ImageHostingMockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testQuAxReturnsAbsoluteURL() async throws {
        ImageHostingMockURLProtocol.data = Data(#"{"success":true,"files":[{"url":"https://qu.ax/abc"}]}"#.utf8)
        let host = QuAxHost(session: makeSession())

        let result = try await host.upload(Data("image".utf8), filename: "a.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(result.absoluteString, "https://qu.ax/abc")
        XCTAssertEqual(ImageHostingMockURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(ImageHostingMockURLProtocol.lastRequest?.url, QuAxHost.endpoint)
    }

    func testQuAxFailureThrowsUploadFailed() async {
        ImageHostingMockURLProtocol.data = Data(#"{"success":false,"files":[]}"#.utf8)
        let host = QuAxHost(session: makeSession())

        do {
            _ = try await host.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("应抛出上传失败")
        } catch let error as HostError {
            guard case .uploadFailed = error else {
                return XCTFail("应为 .uploadFailed，实际为 \(error)")
            }
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
    }

    func testQuAxEmptyFilesThrowsUploadFailed() async {
        ImageHostingMockURLProtocol.data = Data(#"{"success":true,"files":[]}"#.utf8)
        let host = QuAxHost(session: makeSession())

        do {
            _ = try await host.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("应抛出上传失败")
        } catch let error as HostError {
            guard case .uploadFailed = error else {
                return XCTFail("应为 .uploadFailed，实际为 \(error)")
            }
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
    }

    func testQuAxRejectsNonHTTPURL() async {
        ImageHostingMockURLProtocol.data = Data(#"{"success":true,"files":[{"url":"ftp://qu.ax/abc"}]}"#.utf8)
        let host = QuAxHost(session: makeSession())

        do {
            _ = try await host.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("应抛出坏响应")
        } catch let error as HostError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
    }

    func testTelegraphCompatRejectsInsecureBaseURL() async {
        let host = TelegraphCompatHost(
            baseURL: URL(string: "http://upload.example")!,
            session: makeSession()
        )

        do {
            _ = try await host.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("Basic Auth-compatible host must reject HTTP")
        } catch let error as HostError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
    }

    func testTelegraphCompatResolvesRelativeSourceAgainstDefaultBaseURL() async throws {
        ImageHostingMockURLProtocol.data = Data(#"[{"src":"/file/a.png"}]"#.utf8)
        let host = TelegraphCompatHost(session: makeSession())

        let result = try await host.upload(Data(), filename: "a.png", mimeType: "image/png")

        XCTAssertEqual(result.absoluteString, "https://telegraph-image.pages.dev/file/a.png")
        XCTAssertEqual(ImageHostingMockURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(
            ImageHostingMockURLProtocol.lastRequest?.url?.absoluteString,
            "https://telegraph-image.pages.dev/upload"
        )
    }

    func testTelegraphCompatKeepsAbsoluteSource() async throws {
        ImageHostingMockURLProtocol.data = Data(#"[{"src":"https://cdn.example/x.png"}]"#.utf8)
        let host = TelegraphCompatHost(baseURL: URL(string: "https://upload.example")!,
                                       session: makeSession())

        let result = try await host.upload(Data(), filename: "x.png", mimeType: "image/png")

        XCTAssertEqual(result, URL(string: "https://cdn.example/x.png"))
    }

    func testTelegraphCompatAddsBasicAuthHeader() async throws {
        ImageHostingMockURLProtocol.data = Data(#"[{"src":"/file/a.png"}]"#.utf8)
        let host = TelegraphCompatHost(
            baseURL: URL(string: "https://upload.example")!,
            basicAuth: (user: "alice", pass: "secret"),
            session: makeSession()
        )

        _ = try await host.upload(Data(), filename: "a.png", mimeType: "image/png")

        let authorization = ImageHostingMockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authorization, "Basic YWxpY2U6c2VjcmV0")
    }

    func testMultipartUsesFileFieldAndRandomBoundary() async throws {
        ImageHostingMockURLProtocol.data = Data(#"[{"src":"/file/a.png"}]"#.utf8)
        let host = TelegraphCompatHost(session: makeSession())

        _ = try await host.upload(Data("payload".utf8), filename: "a.png", mimeType: "image/png")

        let request = try XCTUnwrap(ImageHostingMockURLProtocol.lastRequest)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundaryPrefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(boundaryPrefix))
        let boundary = String(contentType.dropFirst(boundaryPrefix.count))
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("--\(boundary)\r\n"))
        XCTAssertTrue(body.contains("--\(boundary)--\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"a.png\""))
    }

    func testUploadServiceFallsBackToNextHost() async throws {
        let firstCounter = ImageHostingCallCounter()
        let secondCounter = ImageHostingCallCounter()
        let first = ImageHostingStub(
            id: "first",
            result: .failure(.transport),
            counter: firstCounter
        )
        let second = ImageHostingStub(
            id: "second",
            result: .success(testURL),
            counter: secondCounter
        )
        let service = ImageUploadService(hosts: [first, second])

        let result = try await service.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(result, testURL)
        let firstCalls = await firstCounter.calls
        let secondCalls = await secondCounter.calls
        XCTAssertEqual(firstCalls, ["first"])
        XCTAssertEqual(secondCalls, ["second"])
    }

    func testUploadServiceThrowsLastErrorWhenAllHostsFail() async {
        let firstCounter = ImageHostingCallCounter()
        let secondCounter = ImageHostingCallCounter()
        let first = ImageHostingStub(
            id: "first",
            result: .failure(.transport),
            counter: firstCounter
        )
        let second = ImageHostingStub(
            id: "second",
            result: .failure(.uploadFailed("last")),
            counter: secondCounter
        )
        let service = ImageUploadService(hosts: [first, second])

        do {
            _ = try await service.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("应抛出最后一个错误")
        } catch let error as HostError {
            XCTAssertEqual(error, .uploadFailed("last"))
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
        let firstCalls = await firstCounter.calls
        let secondCalls = await secondCounter.calls
        XCTAssertEqual(firstCalls, ["first"])
        XCTAssertEqual(secondCalls, ["second"])
    }

    func testUploadServiceWithNoHostsThrowsNoHostsError() async {
        let service = ImageUploadService(hosts: [])

        do {
            _ = try await service.upload(Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("应抛出 no hosts")
        } catch let error as HostError {
            XCTAssertEqual(error, .uploadFailed("no hosts"))
        } catch {
            XCTFail("应为 HostError，实际为 \(error)")
        }
    }
}
