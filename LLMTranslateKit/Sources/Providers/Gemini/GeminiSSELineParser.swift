import Foundation

/// Раздел 6.2 ТЗ + разведка этой сессии: `streamGenerateContent` без
/// `?alt=sse` в URL отдаёт один большой JSON-массив, не построчный SSE —
/// этого нет в таблице ТЗ, добавлено `?alt=sse` в `GeminiProvider`. С этим
/// параметром — обычный `data: {...}`, без терминатора вроде `[DONE]`:
/// конец стрима = закрытие соединения (`SSEStreamCompletionPolicy.closeIsSuccess`).
/// В отличие от Anthropic, тип события не выносится в отдельную `event:`
/// строку — весь чанк самодостаточен, парсер без внутреннего состояния.
struct GeminiSSELineParser: SSEProviderLineParser {
    func parse(line: String) throws -> SSELineEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }

        struct Chunk: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            struct UsageMetadata: Decodable {
                let promptTokenCount: Int?
                let candidatesTokenCount: Int?
            }
            let candidates: [Candidate]?
            let usageMetadata: UsageMetadata?
        }

        guard let decoded = try? JSONDecoder().decode(Chunk.self, from: data) else { return nil }

        if let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined(), !text.isEmpty {
            return .delta(text)
        }
        // Раздел 6.4, п. 4 ТЗ: usage — где провайдер его отдаёт. У Gemini
        // это обычно последний чанк, без текста рядом — если текст и usage
        // придут в одном чанке, отдаём текст (важнее для перевода), usage
        // этого конкретного чанка будет пропущен — приемлемо, пока счётчик
        // (этап 6) не построен.
        if let usage = decoded.usageMetadata {
            return .usage(promptTokens: usage.promptTokenCount, completionTokens: usage.candidatesTokenCount)
        }
        return nil
    }
}
