import Foundation

/// Раздел 6.2 ТЗ: SSE Anthropic Messages API — именованные события
/// (`event: <name>`), данные — на следующей строке (`data: {...}`), в
/// отличие от OpenAI, где тип события живёт внутри самого JSON. Поэтому
/// парсер держит состояние (последнее имя события) между вызовами —
/// `class`, не `struct`, обёрнутый в `@unchecked Sendable` по тому же
/// основанию, что и `OpenAISSEStreamDelegate`: вызывается последовательно
/// с delegate queue одной сетевой попытки.
///
/// Завершение стрима — событие `message_stop`, аналог `[DONE]` у OpenAI, но
/// не строка данных, а именно SSE-событие.
final class AnthropicSSELineParser: SSEProviderLineParser, @unchecked Sendable {
    private var currentEventName: String?
    private var inputTokens: Int?

    func parse(line: String) throws -> SSELineEvent? {
        if line.hasPrefix("event:") {
            currentEventName = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }

        switch currentEventName {
        case "content_block_delta":
            return parseContentBlockDelta(data)
        case "message_start":
            parseMessageStart(data)
            return nil
        case "message_delta":
            return parseMessageDelta(data)
        case "message_stop":
            return .streamDone
        case "error":
            return parseError(data)
        default:
            // `ping`, `content_block_start`/`content_block_stop`,
            // `input_json_delta` (tool use — не используем) — игнорируем.
            return nil
        }
    }

    private func parseContentBlockDelta(_ data: Data) -> SSELineEvent? {
        struct Event: Decodable {
            struct Delta: Decodable {
                let type: String
                let text: String?
            }
            let delta: Delta
        }
        guard let decoded = try? JSONDecoder().decode(Event.self, from: data),
              decoded.delta.type == "text_delta",
              let text = decoded.delta.text, !text.isEmpty else { return nil }
        return .delta(text)
    }

    private func parseMessageStart(_ data: Data) {
        struct Event: Decodable {
            struct Message: Decodable {
                struct Usage: Decodable {
                    let inputTokens: Int
                    enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
                }
                let usage: Usage
            }
            let message: Message
        }
        inputTokens = (try? JSONDecoder().decode(Event.self, from: data))?.message.usage.inputTokens
    }

    private func parseMessageDelta(_ data: Data) -> SSELineEvent? {
        struct Event: Decodable {
            struct Usage: Decodable {
                let outputTokens: Int
                enum CodingKeys: String, CodingKey { case outputTokens = "output_tokens" }
            }
            let usage: Usage
        }
        guard let decoded = try? JSONDecoder().decode(Event.self, from: data) else { return nil }
        return .usage(promptTokens: inputTokens, completionTokens: decoded.usage.outputTokens)
    }

    private func parseError(_ data: Data) -> SSELineEvent {
        struct Event: Decodable {
            struct Body: Decodable { let type: String; let message: String }
            let error: Body
        }
        guard let decoded = try? JSONDecoder().decode(Event.self, from: data) else {
            return .serverError(code: nil, message: "malformed Anthropic error event")
        }
        return .serverError(code: decoded.error.type, message: decoded.error.message)
    }
}
