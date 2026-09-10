import XCTest
@testable import LLMTranslateKit

final class SSELineAssemblerTests: XCTestCase {
    func test_singleChunk_multipleLines() {
        var assembler = SSELineAssembler()
        let lines = assembler.feed(Data("line1\nline2\n".utf8))
        XCTAssertEqual(lines, ["line1", "line2"])
    }

    func test_handlesCRLF() {
        var assembler = SSELineAssembler()
        let lines = assembler.feed(Data("line1\r\nline2\r\n".utf8))
        XCTAssertEqual(lines, ["line1", "line2"])
    }

    /// Раздел 14, п. 2 ТЗ: поток с разорванным на границе чанка JSON.
    func test_lineSplitAcrossTwoChunks_reassembledCorrectly() {
        var assembler = SSELineAssembler()
        let firstHalf = #"data: {"choices":[{"delta":{"content":"Hel"#
        let secondHalf = #"lo"}}]}"#

        let firstResult = assembler.feed(Data(firstHalf.utf8))
        XCTAssertEqual(firstResult, [], "строка ещё не завершена — рано отдавать")

        let secondResult = assembler.feed(Data((secondHalf + "\n").utf8))
        XCTAssertEqual(secondResult.count, 1)

        let event = try? OpenAIStreamLineParser.parse(line: secondResult[0])
        XCTAssertEqual(event, .contentDelta("Hello"))
    }

    func test_splitExactlyOnNewlineByte_doesNotLoseOrDuplicateLines() {
        var assembler = SSELineAssembler()
        let first = assembler.feed(Data("data: [DONE]\n".utf8))
        let second = assembler.feed(Data("data: extra\n".utf8))
        XCTAssertEqual(first, ["data: [DONE]"])
        XCTAssertEqual(second, ["data: extra"])
    }

    /// Раздел 14, п. 2 ТЗ: преждевременный обрыв соединения — то, что не
    /// успело закончиться `\n`, когда сеть отвалилась.
    func test_finish_returnsUnterminatedTrailingLine() {
        var assembler = SSELineAssembler()
        _ = assembler.feed(Data(#"data: {"choices":[{"delta":{"content":"partial"#.utf8))
        let leftover = assembler.finish()
        XCTAssertEqual(leftover, #"data: {"choices":[{"delta":{"content":"partial"#)
    }

    func test_finish_returnsNilWhenBufferIsEmpty() {
        var assembler = SSELineAssembler()
        _ = assembler.feed(Data("data: [DONE]\n".utf8))
        XCTAssertNil(assembler.finish())
    }
}

final class OpenAIStreamLineParserTests: XCTestCase {
    /// Раздел 14, п. 2 ТЗ: нормальный поток.
    func test_parsesContentDelta() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Hola"}}]}"#
        XCTAssertEqual(try OpenAIStreamLineParser.parse(line: line), .contentDelta("Hola"))
    }

    func test_parsesDoneSentinel() throws {
        XCTAssertEqual(try OpenAIStreamLineParser.parse(line: "data: [DONE]"), .done)
    }

    func test_ignoresNonDataLines() throws {
        XCTAssertNil(try OpenAIStreamLineParser.parse(line: ""))
        XCTAssertNil(try OpenAIStreamLineParser.parse(line: ": keep-alive comment"))
        XCTAssertNil(try OpenAIStreamLineParser.parse(line: "event: ping"))
    }

    func test_ignoresDeltaWithoutContent() throws {
        // Например, чанк с ролью или finish_reason, без текста.
        let line = #"data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}"#
        XCTAssertNil(try OpenAIStreamLineParser.parse(line: line))
    }

    /// Раздел 14, п. 2 ТЗ: поток с ошибкой в середине.
    func test_parsesServerErrorEvent() throws {
        let line = #"data: {"error":{"message":"rate limited","code":"rate_limit_exceeded"}}"#
        XCTAssertEqual(
            try OpenAIStreamLineParser.parse(line: line),
            .serverError(code: "rate_limit_exceeded", message: "rate limited")
        )
    }

    func test_malformedJSON_throws() {
        let line = #"data: {"choices":[{"delta":{"content":"#  // обрезанный, невосстановимый JSON
        XCTAssertThrowsError(try OpenAIStreamLineParser.parse(line: line)) { error in
            guard case OpenAIStreamParsingError.malformedJSON = error else {
                return XCTFail("ожидалась malformedJSON, получено \(error)")
            }
        }
    }
}
