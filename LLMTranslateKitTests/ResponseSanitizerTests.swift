import XCTest
@testable import LLMTranslateKit

final class ResponseSanitizerTests: XCTestCase {
    func test_stripsWrappingQuotes_whenOriginalHadNone() {
        let result = ResponseSanitizer.sanitize("\"Hello\"", original: "Привет")
        XCTAssertEqual(result, "Hello")
    }

    func test_keepsWrappingQuotes_whenOriginalHadTheSameOnes() {
        let result = ResponseSanitizer.sanitize("\"Hello\"", original: "\"Привет\"")
        XCTAssertEqual(result, "\"Hello\"")
    }

    func test_doesNotTouchNestedQuotesInOriginal() {
        // Оригинал содержит кавычки не по краям — не должно влиять на решение.
        let result = ResponseSanitizer.sanitize("\"He said hi\"", original: "Он сказал \"привет\" мне")
        XCTAssertEqual(result, "He said hi")
    }

    func test_stripsKnownLeadingPrefixes_caseInsensitive() {
        XCTAssertEqual(ResponseSanitizer.sanitize("Перевод: Hello", original: "x"), "Hello")
        XCTAssertEqual(ResponseSanitizer.sanitize("ПЕРЕВОД: Hello", original: "x"), "Hello")
        XCTAssertEqual(ResponseSanitizer.sanitize("Translation: Hello", original: "x"), "Hello")
        XCTAssertEqual(ResponseSanitizer.sanitize("Вот перевод: Hello", original: "x"), "Hello")
        XCTAssertEqual(ResponseSanitizer.sanitize("На изображении: Hello", original: "x"), "Hello")
    }

    func test_doesNotStripPrefixNotAtStart() {
        let result = ResponseSanitizer.sanitize("Hello Перевод: world", original: "x")
        XCTAssertEqual(result, "Hello Перевод: world")
    }

    func test_stripsWrappingCodeFence_whenOriginalHadNone() {
        let result = ResponseSanitizer.sanitize("```\nHello\n```", original: "Привет")
        XCTAssertEqual(result, "Hello")
    }

    func test_stripsCodeFenceWithLanguageTag() {
        let result = ResponseSanitizer.sanitize("```text\nHello\n```", original: "Привет")
        XCTAssertEqual(result, "Hello")
    }

    func test_keepsCodeFence_whenOriginalHadOne() {
        let result = ResponseSanitizer.sanitize("```\nHello\n```", original: "```\nПривет\n```")
        XCTAssertEqual(result, "```\nHello\n```")
    }

    func test_trimsLeadingAndTrailingEmptyLines() {
        let result = ResponseSanitizer.sanitize("\n\n  \nHello\n\n\n", original: "Привет")
        XCTAssertEqual(result, "Hello")
    }

    func test_preservesInternalBlankLinesAndFormatting() {
        let input = "Первая строка\n\nВторая строка"
        let result = ResponseSanitizer.sanitize(input, original: "x")
        XCTAssertEqual(result, input)
    }

    func test_emptyResponse_staysEmpty() {
        XCTAssertEqual(ResponseSanitizer.sanitize("", original: "x"), "")
    }

    func test_combinesPrefixAndQuotesAndTrimming() {
        let result = ResponseSanitizer.sanitize("\n\nВот перевод: \"Hello\"\n\n", original: "Привет")
        XCTAssertEqual(result, "Hello")
    }
}
