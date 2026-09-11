import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 3 ТЗ v1.2: парсинг SSE Gemini (с `?alt=sse`) — нормальный
/// поток, `usage`, отсутствие терминатора (конец = закрытие соединения, это
/// проверяется на уровне `SSEStreamCompletionPolicy`, не здесь).
final class GeminiStreamParsingTests: XCTestCase {
    func test_parsesContentDelta() throws {
        let parser = GeminiSSELineParser()
        let line = #"data: {"candidates":[{"content":{"parts":[{"text":"Hola"}],"role":"model"}}]}"#
        XCTAssertEqual(try parser.parse(line: line), .delta("Hola"))
    }

    func test_joinsMultiplePartsInOneChunk() throws {
        let parser = GeminiSSELineParser()
        let line = #"data: {"candidates":[{"content":{"parts":[{"text":"Hola "},{"text":"mundo"}]}}]}"#
        XCTAssertEqual(try parser.parse(line: line), .delta("Hola mundo"))
    }

    func test_parsesUsageMetadata_whenNoTextInChunk() throws {
        let parser = GeminiSSELineParser()
        let line = #"data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":34}}"#
        XCTAssertEqual(try parser.parse(line: line), .usage(promptTokens: 12, completionTokens: 34))
    }

    func test_ignoresNonDataLines() throws {
        let parser = GeminiSSELineParser()
        XCTAssertNil(try parser.parse(line: ""))
        XCTAssertNil(try parser.parse(line: ": keep-alive"))
    }

    func test_malformedJSON_returnsNilRatherThanThrowing() throws {
        let parser = GeminiSSELineParser()
        XCTAssertNil(try parser.parse(line: #"data: {"candidates":[{"#))
    }
}
