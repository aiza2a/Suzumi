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
