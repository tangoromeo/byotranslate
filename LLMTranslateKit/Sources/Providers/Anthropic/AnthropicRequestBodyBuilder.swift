import Foundation

/// Раздел 6.2/6.3 ТЗ: сборка тела запроса Anthropic Messages API отдельно от
/// `URLRequest` — тестируется снапшотами JSON без реальной сети (раздел 15,
/// п. 10 ТЗ). В отличие от OpenAI-совместимого формата, системный промпт —
/// отдельное верхнеуровневое поле `system`, не сообщение в `messages`.
public enum AnthropicRequestBodyBuilder {
    public static func body(for request: TranslationRequest, model: String) -> [String: Any] {
        let userContent: Any
        switch request.payload {
        case let .text(text):
            userContent = text
        case let .image(data, mime):
            // Раздел 6.3 ТЗ: изображение первым блоком, текст — вторым.
            let base64 = data.base64EncodedString()
            userContent = [
                ["type": "image", "source": ["type": "base64", "media_type": mime, "data": base64]],
                ["type": "text", "text": ""],
            ] as [Any]
        }

        return [
            "model": model,
            "stream": true,
            "max_tokens": request.maxOutputTokens,
            "system": request.systemPrompt,
            "messages": [
                ["role": "user", "content": userContent],
            ],
        ]
    }
}
