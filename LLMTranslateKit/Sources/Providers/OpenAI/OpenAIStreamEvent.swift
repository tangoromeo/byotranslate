import Foundation

/// Раздел 6.2 ТЗ: SSE, `data: {...}`, дельта в `choices[0].delta.content`,
/// терминатор `data: [DONE]`.
public enum OpenAIStreamEvent: Sendable, Equatable {
    case contentDelta(String)
    case done
    /// Раздел 14, п. 2 ТЗ: «поток с ошибкой в середине» — некоторые
    /// OpenAI-совместимые бэкенды шлют `data: {"error": {...}}` вместо
    /// обрыва соединения.
    case serverError(code: String?, message: String)
}

public enum OpenAIStreamParsingError: Error, Sendable, Equatable {
    case malformedJSON(String)
}

public enum OpenAIStreamLineParser {
    private struct ErrorPayload: Decodable {
        struct Body: Decodable {
            let message: String
            let code: String?
        }
        let error: Body
    }

    private struct DeltaPayload: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    /// `nil` для строк, не несущих событие (пустые строки, `event:`/`:`-комментарии
    /// в SSE, строки без префикса `data: `).
    public static func parse(line: String) throws -> OpenAIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .done }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAIStreamParsingError.malformedJSON(payload)
        }

        if let errorPayload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            return .serverError(code: errorPayload.error.code, message: errorPayload.error.message)
        }

        do {
            let decoded = try JSONDecoder().decode(DeltaPayload.self, from: data)
            guard let content = decoded.choices?.first?.delta?.content, !content.isEmpty else {
                return nil // чанк без текстового содержимого (роль, finish_reason и т. п.) — не ошибка.
            }
            return .contentDelta(content)
        } catch {
            throw OpenAIStreamParsingError.malformedJSON(payload)
        }
    }
}
