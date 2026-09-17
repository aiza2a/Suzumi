import XCTest
@testable import Suzuri

final class PageDecodingTests: XCTestCase {
    func testPageListDecodesTotalCountAndPages() throws {
        let json = #"""
        {
          "total_count": 2,
          "pages": [
            {
              "path": "first-page",
              "url": "https://telegra.ph/first-page",
              "title": "第一篇",
              "description": "摘要",
              "author_name": "Suzuri",
              "author_url": "https://example.com",
              "image_url": "https://cdn.example/cover.jpg",
              "views": 12,
              "can_edit": true
            },
            {
              "path": "second-page",
              "url": "https://telegra.ph/second-page",
              "title": "第二篇",
              "description": "",
              "views": 0,
              "can_edit": false
            }
          ]
        }
        """#

        let result = try JSONDecoder().decode(PageList.self, from: Data(json.utf8))

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.pages.map(\.path), ["first-page", "second-page"])
        XCTAssertEqual(result.pages[0].authorName, "Suzuri")
        XCTAssertEqual(result.pages[0].imageUrl, "https://cdn.example/cover.jpg")
        XCTAssertTrue(result.pages[0].canEdit)
    }

    func testPageDecodesTopLevelStringContentAsParagraphs() throws {
        let json = #"""
        {
          "path":"plain-content",
          "url":"https://telegra.ph/plain-content",
          "title":"纯文本",
          "description":"",
          "content":["第一段","第二段"],
          "views":0,
          "can_edit":false
        }
        """#

        let page = try JSONDecoder().decode(Page.self, from: Data(json.utf8))

        let firstNode = try XCTUnwrap(page.content?.first)
        let secondNode = try XCTUnwrap(page.content?[1])
        XCTAssertEqual(firstNode.tag, "p")
        XCTAssertEqual(secondNode.tag, "p")
        guard case let .text(firstText) = firstNode.children?.first else {
            return XCTFail("Expected first text child")
        }
        guard case let .text(secondText) = secondNode.children?.first else {
            return XCTFail("Expected second text child")
        }
        XCTAssertEqual(firstText, "第一段")
        XCTAssertEqual(secondText, "第二段")
    }

    func testPageDecodesMixedStringAndNodeContent() throws {
        let json = #"""
        {
          "path":"mixed-content",
          "url":"https://telegra.ph/mixed-content",
          "title":"混合内容",
          "description":"",
          "content":["文字", {"tag":"hr"}],
          "views":0,
          "can_edit":false
        }
        """#

        let page = try JSONDecoder().decode(Page.self, from: Data(json.utf8))
        let content = try XCTUnwrap(page.content)
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0].tag, "p")
        XCTAssertEqual(content[1].tag, "hr")
    }

    func testPageDecodesCanEditFalse() throws {
        let json = #"""
        {
          "path":"read-only",
          "url":"https://telegra.ph/read-only",
          "title":"只读页",
          "description":"内容",
          "author_name":null,
          "author_url":null,
          "image_url":null,
          "content":null,
          "views":7,
          "can_edit":false
        }
        """#

        let page = try JSONDecoder().decode(Page.self, from: Data(json.utf8))

        XCTAssertEqual(page.id, "read-only")
        XCTAssertFalse(page.canEdit)
        XCTAssertEqual(page.views, 7)
        XCTAssertNil(page.content)
    }

    func testMissingCanEditFieldCanReuseListPermission() throws {
        let json = #"""
        {
          "path":"detail",
          "url":"https://telegra.ph/detail",
          "title":"详情",
          "description":"",
          "views":0
        }
        """#
        let detail = try JSONDecoder().decode(Page.self, from: Data(json.utf8))
        let listPage = Page(
            path: "detail",
            url: "https://telegra.ph/detail",
            title: "详情",
            description: "",
            canEdit: true
        )

        let preserved = detail.preservingCanEdit(from: listPage)

        XCTAssertFalse(detail.hasCanEditField)
        XCTAssertTrue(preserved.canEdit)
    }

    func testPageEncodingUsesSnakeCaseKeys() throws {
        let page = Page(
            path: "p",
            url: "https://telegra.ph/p",
            title: "标题",
            description: "摘要",
            authorName: "作者",
            authorUrl: "https://example.com",
            imageUrl: nil,
            content: nil,
            views: 1,
            canEdit: true
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(page),
                options: []
            ) as? [String: Any]
        )

        XCTAssertEqual(object["author_name"] as? String, "作者")
        XCTAssertEqual(object["author_url"] as? String, "https://example.com")
        XCTAssertEqual(object["can_edit"] as? Bool, true)
        XCTAssertNil(object["authorName"])
    }
}
