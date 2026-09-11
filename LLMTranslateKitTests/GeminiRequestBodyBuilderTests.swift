import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 10 ТЗ v1.2: сборка тела запроса Gemini — сверка со снапшотами JSON.
final class GeminiRequestBodyBuilderTests: XCTestCase {
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
        let body = GeminiRequestBodyBuilder.body(for: request)
        let expected: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "Hello"]]],
            ],
            "systemInstruction": ["parts": [["text": "translate"]]],
            "generationConfig": ["maxOutputTokens": 2048],
        ]
        XCTAssertEqual(try normalizedJSON(body), try normalizedJSON(expected))
    }

    /// Раздел 6.3 ТЗ: `inline_data` первым блоком, `text` — вторым.
    func test_imagePayload_snapshot() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let request = TranslationRequest(
            payload: .image(imageData, mime: "image/jpeg"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate image",
            maxOutputTokens: 2048
        )
        let body = GeminiRequestBodyBuilder.body(for: request)
        let base64 = imageData.base64EncodedString()
        let expected: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                        ["text": ""],
                    ],
                ],
            ],
            "systemInstruction": ["parts": [["text": "translate image"]]],
            "generationConfig": ["maxOutputTokens": 2048],
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
        let body = GeminiRequestBodyBuilder.body(for: request)
        guard
            let contents = body["contents"] as? [[String: Any]],
            let userContent = contents.first,
            let parts = userContent["parts"] as? [[String: Any]],
            let inlinePart = parts.first(where: { $0["inline_data"] != nil }),
            let inlineData = inlinePart["inline_data"] as? [String: String]
        else {
            return XCTFail("не удалось разобрать структуру parts для inline_data")
        }
        XCTAssertEqual(inlineData["mime_type"], "image/png")
        XCTAssertEqual(inlineData["data"], imageData.base64EncodedString())
    }
}
