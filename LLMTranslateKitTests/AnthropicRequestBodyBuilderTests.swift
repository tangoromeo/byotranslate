import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 10 ТЗ v1.2: сборка тела запроса Anthropic — сверка со
/// снапшотами JSON. Тот же приём нормализации, что и у
/// `OpenAIRequestBodyBuilderTests`.
final class AnthropicRequestBodyBuilderTests: XCTestCase {
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
        let body = AnthropicRequestBodyBuilder.body(for: request, model: "claude-test")
        let expected: [String: Any] = [
            "model": "claude-test",
            "stream": true,
            "max_tokens": 2048,
            "system": "translate",
            "messages": [
                ["role": "user", "content": "Hello"],
            ],
        ]
        XCTAssertEqual(try normalizedJSON(body), try normalizedJSON(expected))
    }

    /// Раздел 6.3 ТЗ: content-массив `image` + `text`, изображение первым блоком.
    func test_imagePayload_snapshot() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let request = TranslationRequest(
            payload: .image(imageData, mime: "image/jpeg"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate image",
            maxOutputTokens: 2048
        )
        let body = AnthropicRequestBodyBuilder.body(for: request, model: "claude-vision-test")
        let base64 = imageData.base64EncodedString()
        let expected: [String: Any] = [
            "model": "claude-vision-test",
            "stream": true,
            "max_tokens": 2048,
            "system": "translate image",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                        ["type": "text", "text": ""],
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
        let body = AnthropicRequestBodyBuilder.body(for: request, model: "m")
        guard
            let messages = body["messages"] as? [[String: Any]],
            let userMessage = messages.first,
            let content = userMessage["content"] as? [[String: Any]],
            let imagePart = content.first(where: { $0["type"] as? String == "image" }),
            let source = imagePart["source"] as? [String: String]
        else {
            return XCTFail("не удалось разобрать структуру content для image")
        }
        XCTAssertEqual(source["media_type"], "image/png")
        XCTAssertEqual(source["data"], imageData.base64EncodedString())
    }
}
