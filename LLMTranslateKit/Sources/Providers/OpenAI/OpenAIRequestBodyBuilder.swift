import Foundation

/// Раздел 6.2/6.3 ТЗ: сборка тела запроса отдельно от `URLRequest`, чтобы
/// быть тестируемой снапшотами JSON (раздел 14, п. 7 ТЗ) без реальной сети.
public enum OpenAIRequestBodyBuilder {
    public static func body(for request: TranslationRequest, model: String, baseURL: URL? = nil) -> [String: Any] {
        let userContent: Any
        switch request.payload {
        case let .text(text):
            userContent = text
        case let .image(data, mime):
            // Раздел 6.3 ТЗ: content-массив text+image_url.
            let base64 = data.base64EncodedString()
            userContent = [
                ["type": "text", "text": ""],
                ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(base64)"]],
            ] as [Any]
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": request.maxOutputTokens,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        // Только OpenRouter: у настоящего OpenAI неизвестный параметр `reasoning`
        // вызывает ошибку запроса.
        if request.disableReasoning, isOpenRouter(baseURL) {
            body["reasoning"] = ["enabled": false]
        }
        return body
    }

    static func isOpenRouter(_ baseURL: URL?) -> Bool {
        guard let host = baseURL?.host?.lowercased() else { return false }
        return host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
    }
}
