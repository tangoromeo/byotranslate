import Foundation

/// Раздел 6.2/6.3 ТЗ: сборка тела запроса Gemini `generateContent` отдельно
/// от `URLRequest` — тестируется снапшотами JSON (раздел 15, п. 10 ТЗ).
/// Системный промпт — отдельное поле `systemInstruction`, не часть `contents`.
public enum GeminiRequestBodyBuilder {
    public static func body(for request: TranslationRequest) -> [String: Any] {
        let parts: [[String: Any]]
        switch request.payload {
        case let .text(text):
            parts = [["text": text]]
        case let .image(data, mime):
            // Раздел 6.3 ТЗ: inline_data первым блоком, text — вторым.
            let base64 = data.base64EncodedString()
            parts = [
                ["inline_data": ["mime_type": mime, "data": base64]],
                ["text": ""],
            ]
        }

        return [
            "contents": [
                ["role": "user", "parts": parts],
            ],
            "systemInstruction": ["parts": [["text": request.systemPrompt]]],
            "generationConfig": ["maxOutputTokens": request.maxOutputTokens],
        ]
    }
}
