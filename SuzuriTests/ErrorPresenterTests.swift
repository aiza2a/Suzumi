import XCTest
@testable import Suzuri

final class ErrorPresenterTests: XCTestCase {
    func testAPIErrorHasNonEmptyDistinctMessage() {
        let message = ErrorPresenter.message(for: TelegraphError.api(message: "PAGE_NOT_FOUND"))

        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("PAGE_NOT_FOUND"))
        XCTAssertFalse(ErrorPresenter.isRetryable(TelegraphError.api(message: "PAGE_NOT_FOUND")))
    }

    func testNetworkErrorIsRetryable() {
        let error = TelegraphError.network(underlying: "offline")

        XCTAssertFalse(ErrorPresenter.message(for: error).isEmpty)
        XCTAssertTrue(ErrorPresenter.isRetryable(error))
    }

    func testUnauthorizedHTTPErrorIsNotRetryable() {
        let error = TelegraphError.network(underlying: "HTTP 401")

        XCTAssertFalse(ErrorPresenter.isRetryable(error))
    }

    func testTooManyRequestsIsRetryable() {
        let error = TelegraphError.network(underlying: "HTTP 429")

        XCTAssertTrue(ErrorPresenter.isRetryable(error))
    }

    func testContentTooLargeIsNotRetryable() {
        let error = TelegraphError.contentTooLarge(bytes: 70_000)
        let presenter = ErrorPresenter(error: error)

        XCTAssertEqual(presenter.title, "内容过大")
        XCTAssertTrue(presenter.message.contains("70") || presenter.message.contains("70000"))
        XCTAssertFalse(presenter.canRetry)
    }

    func testImageTransportErrorHasImageSpecificCopy() {
        let message = ErrorPresenter.message(for: HostError.transport)

        XCTAssertTrue(message.contains("图片"))
        XCTAssertTrue(ErrorPresenter.isRetryable(HostError.transport))
    }

    func testMissingTokenHasAccountCopy() {
        let presenter = ErrorPresenter(error: TelegraphError.missingToken)

        XCTAssertEqual(presenter.title, "账号不可用")
        XCTAssertFalse(presenter.message.isEmpty)
        XCTAssertFalse(presenter.canRetry)
    }
}
