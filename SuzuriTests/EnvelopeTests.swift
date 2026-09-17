import XCTest
@testable import Suzuri

final class EnvelopeTests: XCTestCase {

    private func decode(_ json: String) throws -> Envelope<TelegraphAccount> {
        try JSONDecoder().decode(Envelope<TelegraphAccount>.self, from: Data(json.utf8))
    }

    /// ok=true + result → result 非 nil
    func testOkWithResult() throws {
        let env = try decode(#"{"ok":true,"result":{"short_name":"user_abc"}}"#)
        XCTAssertTrue(env.ok)
        XCTAssertNotNil(env.result)
        XCTAssertEqual(env.result?.shortName, "user_abc")
    }

    /// ok=false + error="SHORT_NAME_REQUIRED" → 解码成功，error 字段读出
    func testOkFalseWithError() throws {
        let env = try decode(#"{"ok":false,"error":"SHORT_NAME_REQUIRED"}"#)
        XCTAssertFalse(env.ok)
        XCTAssertNil(env.result)
        XCTAssertEqual(env.error, "SHORT_NAME_REQUIRED")
    }

    /// 缺 result 且 ok=true → result == nil（不崩）
    func testOkTrueNoResult() throws {
        let env = try decode(#"{"ok":true}"#)
        XCTAssertTrue(env.ok)
        XCTAssertNil(env.result)
        XCTAssertNil(env.error)
    }

    /// ok=true + warning error is retained while the result remains usable.
    func testOkTrueWithErrorRetainsBothFields() throws {
        let env = try decode(#"{"ok":true,"error":"WARNING","result":{"short_name":"u"}}"#)

        XCTAssertTrue(env.ok)
        XCTAssertEqual(env.error, "WARNING")
        XCTAssertEqual(env.result?.shortName, "u")
    }

    /// A result on a failed envelope is ignored rather than exposed as success data.
    func testOkFalseWithResultIgnoresResult() throws {
        let env = try decode(#"{"ok":false,"error":"FAILED","result":{"short_name":"stale"}}"#)

        XCTAssertFalse(env.ok)
        XCTAssertEqual(env.error, "FAILED")
        XCTAssertNil(env.result)
    }

    /// Account 的 snake_case 字段能被 Envelope 正确映射
    func testAccountSnakeCaseMapping() throws {
        let env = try decode(#"{"ok":true,"result":{"short_name":"sn","author_name":"an","access_token":"tk","page_count":3}}"#)
        XCTAssertEqual(env.result?.shortName, "sn")
        XCTAssertEqual(env.result?.authorName, "an")
        XCTAssertEqual(env.result?.accessToken, "tk")
        XCTAssertEqual(env.result?.pageCount, 3)
    }
}