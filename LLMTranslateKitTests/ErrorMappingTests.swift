import XCTest
@testable import LLMTranslateKit

/// Раздел 14, п. 4 ТЗ: маппинг ошибок по коду и телу ответа (раздел 11 ТЗ).
final class ErrorMappingTests: XCTestCase {
    private func classify(status: Int, bodyMessage: String? = nil, bodyCode: String? = nil) -> (TranslationError, Bool) {
        OpenAICompatibleProvider.classify(RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: bodyMessage, bodyCode: bodyCode))
    }

    func test_401_mapsToAuthenticationRejected_notRetryable() {
        let (error, canRetry) = classify(status: 401)
        XCTAssertEqual(error, .authenticationRejected)
        XCTAssertFalse(canRetry)
    }

    func test_403_mapsToAuthenticationRejected_notRetryable() {
        let (error, canRetry) = classify(status: 403)
        XCTAssertEqual(error, .authenticationRejected)
        XCTAssertFalse(canRetry)
    }

    func test_429_mapsToRateLimited_isRetryable() {
        let (error, canRetry) = classify(status: 429)
        XCTAssertEqual(error, .rateLimited)
        XCTAssertTrue(canRetry)
    }

    func test_402_mapsToInsufficientQuota_notRetryable() {
        let (error, canRetry) = classify(status: 402)
        XCTAssertEqual(error, .insufficientQuota)
        XCTAssertFalse(canRetry)
    }

    func test_insufficientQuotaBodyCode_overridesStatus() {
        // Некоторые бэкенды шлют insufficient_quota с HTTP 400, не 402.
        let (error, canRetry) = classify(status: 400, bodyCode: "insufficient_quota")
        XCTAssertEqual(error, .insufficientQuota)
        XCTAssertFalse(canRetry)
    }

    func test_404_mapsToModelUnavailable_notRetryable() {
        let (error, canRetry) = classify(status: 404)
        XCTAssertEqual(error, .modelUnavailable)
        XCTAssertFalse(canRetry)
    }

    func test_500_mapsToServerError_isRetryable() {
        let (error, canRetry) = classify(status: 500, bodyMessage: "boom")
        XCTAssertEqual(error, .other(code: "500", message: "boom"))
        XCTAssertTrue(canRetry)
    }

    func test_503_mapsToServerError_isRetryable() {
        let (_, canRetry) = classify(status: 503)
        XCTAssertTrue(canRetry)
    }

    func test_networkError_mapsToTimeoutOrNoNetwork_isRetryable() {
        let raw = RawAttemptFailure(httpStatus: nil, underlying: URLError(.notConnectedToInternet), bodyMessage: nil, bodyCode: nil)
        let (error, canRetry) = OpenAICompatibleProvider.classify(raw)
        XCTAssertEqual(error, .timeoutOrNoNetwork)
        XCTAssertTrue(canRetry)
    }

    func test_streamInterrupted_isNotAutoRetried() {
        let (error, canRetry) = OpenAICompatibleProvider.classify(TranslationError.streamInterrupted)
        XCTAssertEqual(error, .streamInterrupted)
        XCTAssertFalse(canRetry, "уже частично начатый ответ не ретраим автоматически")
    }

    func test_missingAPIKey_passesThroughUnchanged() {
        let (error, canRetry) = OpenAICompatibleProvider.classify(TranslationError.missingAPIKey)
        XCTAssertEqual(error, .missingAPIKey)
        XCTAssertFalse(canRetry)
    }
}
