import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 3 ТЗ v1.2: парсинг SSE Anthropic — нормальный поток, поток
/// с ошибкой в середине, завершение по `message_stop`, `usage`.
final class AnthropicStreamParsingTests: XCTestCase {
    func test_parsesContentBlockDelta_textDelta() throws {
        let parser = AnthropicSSELineParser()
        XCTAssertNil(try parser.parse(line: "event: content_block_delta"))
        let event = try parser.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hola"}}"#)
        XCTAssertEqual(event, .delta("Hola"))
    }

    func test_ignoresNonTextDelta() throws {
        // input_json_delta — tool use, не используем в переводе.
        let parser = AnthropicSSELineParser()
        _ = try parser.parse(line: "event: content_block_delta")
        let event = try parser.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#)
        XCTAssertNil(event)
    }

    func test_ignoresPingAndBlockLifecycleEvents() throws {
        let parser = AnthropicSSELineParser()
        _ = try parser.parse(line: "event: ping")
        XCTAssertNil(try parser.parse(line: #"data: {"type":"ping"}"#))
        _ = try parser.parse(line: "event: content_block_start")
        XCTAssertNil(try parser.parse(line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#))
    }

    /// `message_stop` — аналог `[DONE]` у OpenAI, но SSE-событие, не строка данных.
    func test_messageStop_isStreamDone() throws {
        let parser = AnthropicSSELineParser()
        _ = try parser.parse(line: "event: message_stop")
        let event = try parser.parse(line: #"data: {"type":"message_stop"}"#)
        XCTAssertEqual(event, .streamDone)
    }

    /// `message_start` несёт входные токены, `message_delta` — выходные;
    /// событие `.usage` собирается из обоих.
    func test_messageStartThenMessageDelta_producesUsage() throws {
        let parser = AnthropicSSELineParser()
        _ = try parser.parse(line: "event: message_start")
        XCTAssertNil(try parser.parse(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":42,"output_tokens":0}}}"#))

        _ = try parser.parse(line: "event: message_delta")
        let event = try parser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":17}}"#)
        XCTAssertEqual(event, .usage(promptTokens: 42, completionTokens: 17))
    }

    /// Раздел 15, п. 3 ТЗ: поток с ошибкой в середине.
    func test_parsesErrorEvent() throws {
        let parser = AnthropicSSELineParser()
        _ = try parser.parse(line: "event: error")
        let event = try parser.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        XCTAssertEqual(event, .serverError(code: "overloaded_error", message: "Overloaded"))
    }

    func test_dataLineWithoutPrecedingEvent_isIgnored() throws {
        let parser = AnthropicSSELineParser()
        XCTAssertNil(try parser.parse(line: #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"stray"}}"#))
    }

    func test_emptyAndCommentLines_areIgnored() throws {
        let parser = AnthropicSSELineParser()
        XCTAssertNil(try parser.parse(line: ""))
        XCTAssertNil(try parser.parse(line: ": keep-alive"))
    }
}
