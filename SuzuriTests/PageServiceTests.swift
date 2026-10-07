import Foundation
import XCTest
@testable import Suzuri

private final class PageServiceMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var data: Data?
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = URLRequestTestSupport.materializedBody(request)
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
        if let data = Self.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class PageServiceTests: XCTestCase {
    private let pageJSON = #"""
    {
      "path":"demo-page",
      "url":"https://telegra.ph/demo-page",
      "title":"Demo",
      "description":"A demo page",
      "author_name":"Author",
      "author_url":"",
      "image_url":null,
      "content":[{"tag":"p","children":["正文"]}],
      "views":3,
      "can_edit":true
    }
    """#

    private func makeService() -> PageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PageServiceMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            baseURL: URL(string: "https://api.telegra.ph")!,
            session: session,
            accessToken: "token"
        )
        return PageService(client: client)
    }

    private func formValue(_ name: String, from request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let encoded = String(data: body, encoding: .utf8)
        else { return nil }
        for pair in encoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].removingPercentEncoding == name
            else { continue }
            return parts[1]
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
        }
        return nil
    }
    private func formValue(_ name: String, from parameters: [String: String]) -> String? {
        parameters[name]
    }

    override func setUp() {
        super.setUp()
        PageServiceMockURLProtocol.data = nil
        PageServiceMockURLProtocol.statusCode = 200
        PageServiceMockURLProtocol.error = nil
        PageServiceMockURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        PageServiceMockURLProtocol.data = nil
        PageServiceMockURLProtocol.statusCode = 200
        PageServiceMockURLProtocol.error = nil
        PageServiceMockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testGetPageListDecodesPagesAndTotal() async throws {
        let json = #"""
        {
          "ok":true,
          "result":{
            "total_count":51,
            "pages":[
              {
                "path":"demo-page",
                "url":"https://telegra.ph/demo-page",
                "title":"Demo",
                "description":"摘要",
                "views":3,
                "can_edit":false
              }
            ]
          }
        }
        """#
        PageServiceMockURLProtocol.data = Data(json.utf8)

        let result = try await makeService().getPageList(offset: 0)

        XCTAssertEqual(result.total, 51)
        XCTAssertEqual(result.pages.first?.path, "demo-page")
        XCTAssertEqual(PageServiceMockURLProtocol.lastRequest?.httpMethod, "GET")
        let query = URLComponents(url: try XCTUnwrap(PageServiceMockURLProtocol.lastRequest?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "limit" })?.value, "50")
    }

    func testGetPageRequestsContentAndPath() async throws {
        PageServiceMockURLProtocol.data = Data(#"{"ok":true,"result":PLACEHOLDER}"#.replacingOccurrences(of: "PLACEHOLDER", with: pageJSON).utf8)

        let page = try await makeService().getPage(path: "demo-page", returnContent: true)

        XCTAssertEqual(page.path, "demo-page")
        let request = try XCTUnwrap(PageServiceMockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/getPage/demo-page")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "return_content" })?.value, "true")
    }

    func testEditPageSendsContentAndReturnsPage() async throws {
        PageServiceMockURLProtocol.data = Data(#"{"ok":true,"result":PLACEHOLDER}"#.replacingOccurrences(of: "PLACEHOLDER", with: pageJSON).utf8)
        let node = TelegraphNode(tag: "p", attrs: nil, children: [.text("更新")])
        let service = makeService()

        let page = try await service.editPage(
            path: "demo-page",
            title: "新标题",
            authorName: "作者",
            authorUrl: nil,
            content: [node]
        )

        XCTAssertEqual(page.title, "Demo")
        let request = try XCTUnwrap(PageServiceMockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/editPage/demo-page")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        let body = try service.parameters(title: "新标题", authorName: "作者", authorUrl: nil, content: [node])
        XCTAssertEqual(formValue("title", from: body), "新标题")
        XCTAssertEqual(formValue("author_name", from: body), "作者")
        XCTAssertTrue(formValue("content", from: body)?.contains("更新") == true)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "access_token" })?.value, "token")
    }

    func testCreatePageReturnsPage() async throws {
        PageServiceMockURLProtocol.data = Data(#"{"ok":true,"result":PLACEHOLDER}"#.replacingOccurrences(of: "PLACEHOLDER", with: pageJSON).utf8)
        let service = makeService()

        let page = try await service.createPage(
            title: "标题",
            authorName: nil,
            authorUrl: nil,
            content: []
        )

        XCTAssertEqual(page.url, "https://telegra.ph/demo-page")
        let request = try XCTUnwrap(PageServiceMockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try service.parameters(title: "标题", authorName: nil, authorUrl: nil, content: [])
        XCTAssertEqual(formValue("title", from: body), "标题")
        XCTAssertEqual(formValue("return_content", from: body), "true")
        XCTAssertEqual(request.url?.path, "/createPage")
    }

    func testBlockCreateOverloadDropsEmptyBlocksBeforeEncoding() throws {
        let blocks: [Block] = [
            .emptyParagraph(),
            .paragraph(id: UUID(), text: "保留正文")
        ]
        let body = try makeService().parameters(
            title: "标题",
            authorName: nil,
            authorUrl: nil,
            blocks: blocks
        )

        let content = try XCTUnwrap(formValue("content", from: body))
        let nodes = try JSONDecoder().decode([TelegraphNode].self, from: Data(content.utf8))
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.tag, "p")
        guard case let .text(text) = try XCTUnwrap(nodes.first?.children?.first) else {
            return XCTFail("应编码为正文节点")
        }
        XCTAssertEqual(text, "保留正文")
    }

    func testContentOver64KiBThrowsBeforeNetworkRequest() async throws {
        let hugeNode = TelegraphNode(
            tag: "p",
            attrs: nil,
            children: [.text(String(repeating: "x", count: 70_000))]
        )

        do {
            _ = try await makeService().createPage(
                title: "过大",
                authorName: nil,
                authorUrl: nil,
                content: [hugeNode]
            )
            XCTFail("应抛出 contentTooLarge")
        } catch let error as TelegraphError {
            guard case .contentTooLarge(let bytes) = error else {
                return XCTFail("应为 contentTooLarge，实际为 \(error)")
            }
            XCTAssertGreaterThan(bytes, BlockEncoder.maxContentBytes)
        }
        XCTAssertNil(PageServiceMockURLProtocol.lastRequest)
    }
}
