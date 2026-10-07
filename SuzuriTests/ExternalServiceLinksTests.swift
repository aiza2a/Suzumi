import Foundation
import XCTest
@testable import Suzuri

final class ExternalServiceLinksTests: XCTestCase {
    func testPostimagesAcceptsOnlyImageDirectLinks() throws {
        let url = try PostimagesLink.validatedURL("  https://i.postimg.cc/AbC123/photo.jpg\n")
        XCTAssertEqual(url.absoluteString, "https://i.postimg.cc/AbC123/photo.jpg")
        for invalid in [
            "https://postimg.cc/AbC123", "http://i.postimg.cc/a/b.jpg",
            "https://i.postimg.cc.evil.example/a/b.jpg", "https://i.postimg.cc@evil.example/a/b.jpg",
            "https://user@i.postimg.cc/a/b.jpg", "https://i.postimg.cc:8443/a/b.jpg",
            "https://i.postimg.cc/a/page.html", "[img]https://i.postimg.cc/a/b.jpg[/img]"
        ] {
            XCTAssertThrowsError(try PostimagesLink.validatedURL(invalid), invalid)
        }
    }

    func testTelegraphAuthorizationLinkDoesNotAllowOtherHostsOrPaths() throws {
        XCTAssertEqual(try TelegraphLoginLink.validatedURL("https://edit.telegra.ph/auth/Example_123").host, "edit.telegra.ph")
        for invalid in [
            "https://evil.example/auth/123", "http://edit.telegra.ph/auth/123",
            "https://edit.telegra.ph.evil.example/auth/123", "https://edit.telegra.ph/auth/123?redirect=https://evil.example",
            "https://edit.telegra.ph/a-story", "https://edit.telegra.ph/auth/",
            "https://user:pass@edit.telegra.ph/auth/123", "https://edit.telegra.ph:8443/auth/123"
        ] {
            XCTAssertThrowsError(try TelegraphLoginLink.validatedURL(invalid), invalid)
        }
    }

    func testCookieCandidatesRequireTrustedDomainAndPreferTokenNameWithoutAssumingIt() {
        let cookies = [
            cookie(name: "tph_uuid", value: "tracking", domain: ".telegra.ph"),
            cookie(name: "tph_token", value: "wrong-host", domain: ".evil.example"),
            cookie(name: "tph_token", value: "expected", domain: ".telegra.ph")
        ]
        XCTAssertEqual(TelegraphLoginLink.tokenCandidates(from: cookies), ["expected", "tracking"])
        XCTAssertEqual(TelegraphLoginLink.tokenCandidates(from: [cookies[0], cookies[1]]), ["tracking"])
        XCTAssertTrue(TelegraphLoginLink.tokenCandidates(from: [cookie(name: "tph_token", value: "x", domain: "telegra.ph.evil.example")]).isEmpty)
        XCTAssertEqual(TelegraphLoginLink.tokenCandidates(from: [cookie(name: "new_cookie_name", value: "candidate", domain: "edit.telegra.ph")]), ["candidate"])
        let insecure = HTTPCookie(properties: [.name: "token", .value: "insecure", .domain: "telegra.ph", .path: "/"])!
        XCTAssertTrue(TelegraphLoginLink.tokenCandidates(from: [insecure]).isEmpty)
        XCTAssertEqual(TelegraphLoginLink.tokenCandidates(from: [cookies[2], cookies[2]]), ["expected"])
    }

    func testCookieCandidatesContinueOnlyAfterExplicitInvalidTokenResponse() {
        XCTAssertTrue(TelegraphLoginLink.isInvalidTokenResponse(TelegraphError.api(message: "ACCESS_TOKEN_INVALID")))
        XCTAssertFalse(TelegraphLoginLink.isInvalidTokenResponse(TelegraphError.network(underlying: "HTTP 403")))
        XCTAssertFalse(TelegraphLoginLink.isInvalidTokenResponse(TelegraphError.api(message: "账号或服务器已改变")))
        XCTAssertFalse(TelegraphLoginLink.isInvalidTokenResponse(CancellationError()))
    }

    private func cookie(name: String, value: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"])!
    }
}
