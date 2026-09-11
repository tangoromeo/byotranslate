import XCTest
@testable import LLMTranslateKit

/// Раздел 14, п. 7 ТЗ: сборка тела запроса с изображением (и текстом, для
/// контроля регрессии) — сверка со снапшотами JSON.
///
/// Снапшот сверяется не как сырая строка (экранирование `/` в
/// `JSONSerialization` — деталь реализации, из-за которой ручной строковый
/// литерал легко разъезжается), а через `JSONSerialization`, применённую к
/// независимо построенному ожидаемому словарю, и сравнение уже
/// нормализованных строк.
final class OpenAIRequestBodyBuilderTests: XCTestCase {
    private func normalizedJSON(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func test_textPayload_snapshot() throws {
        let request = TranslationRequest(
            payload: .text("Hello"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate",
            maxOutputTokens: 2048
        )
        let body = OpenAIRequestBodyBuilder.body(for: request, model: "gpt-4o-mini")
        let expected: [String: Any] = [
            "model": "gpt-4o-mini",
            "stream": true,
            "max_tokens": 2048,
            "messages": [
                ["role": "system", "content": "translate"],
                ["role": "user", "content": "Hello"],
            ],
        ]
        XCTAssertEqual(try normalizedJSON(body), try normalizedJSON(expected))
    }

    /// Раздел 6.3 ТЗ: content-массив `text` + `image_url` с data-URL.
    func test_imagePayload_snapshot() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF]) // огрызок JPEG, для теста хватит трёх байт
        let request = TranslationRequest(
            payload: .image(imageData, mime: "image/jpeg"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate image",
            maxOutputTokens: 2048
        )
        let body = OpenAIRequestBodyBuilder.body(for: request, model: "gpt-4o")
        let base64 = imageData.base64EncodedString()
        let expected: [String: Any] = [
            "model": "gpt-4o",
            "stream": true,
            "max_tokens": 2048,
            "messages": [
                ["role": "system", "content": "translate image"],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": ""],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                    ],
                ],
            ],
        ]
        XCTAssertEqual(try normalizedJSON(body), try normalizedJSON(expected))
    }

    func test_imagePayload_usesProvidedMimeType() throws {
        let imageData = Data([0x89, 0x50])
        let request = TranslationRequest(
            payload: .image(imageData, mime: "image/png"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "en"),
            systemPrompt: "x"
        )
        let body = OpenAIRequestBodyBuilder.body(for: request, model: "m")
        guard
            let messages = body["messages"] as? [[String: Any]],
            let userMessage = messages.last,
            let content = userMessage["content"] as? [[String: Any]],
            let imagePart = content.first(where: { $0["type"] as? String == "image_url" }),
            let imageURL = imagePart["image_url"] as? [String: String]
        else {
            return XCTFail("не удалось разобрать структуру content для image_url")
        }
        XCTAssertEqual(imageURL["url"], "data:image/png;base64,\(imageData.base64EncodedString())")
    }
}
