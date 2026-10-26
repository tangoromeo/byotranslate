import XCTest
@testable import LLMTranslateKit

/// Отключение размышления: параметр уходит только на OpenRouter.
final class ReasoningFlagTests: XCTestCase {
    private func request(disable: Bool) -> TranslationRequest {
        TranslationRequest(
            payload: .text("Hello"),
            detectedSourceLanguage: nil,
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate",
            disableReasoning: disable
        )
    }

    private let openRouter = URL(string: "https://openrouter.ai/api/v1")!
    private let openAI = URL(string: "https://api.openai.com/v1")!

    func test_openRouter_withFlag_sendsReasoningDisabled() {
        let body = OpenAIRequestBodyBuilder.body(for: request(disable: true), model: "m", baseURL: openRouter)
        let reasoning = body["reasoning"] as? [String: Bool]
        XCTAssertEqual(reasoning, ["enabled": false])
    }

    func test_openRouter_withoutFlag_sendsNothing() {
        let body = OpenAIRequestBodyBuilder.body(for: request(disable: false), model: "m", baseURL: openRouter)
        XCTAssertNil(body["reasoning"])
    }

    func test_otherProviders_neverGetReasoningParameter() {
        // у настоящего OpenAI неизвестный параметр вызывает ошибку запроса
        XCTAssertNil(OpenAIRequestBodyBuilder.body(for: request(disable: true), model: "m", baseURL: openAI)["reasoning"])
        XCTAssertNil(OpenAIRequestBodyBuilder.body(for: request(disable: true), model: "m", baseURL: nil)["reasoning"])
    }

    func test_lookalikeHost_isNotOpenRouter() {
        let fake = URL(string: "https://openrouter.ai.evil.example/v1")!
        XCTAssertNil(OpenAIRequestBodyBuilder.body(for: request(disable: true), model: "m", baseURL: fake)["reasoning"])
    }

    func test_slotConfig_defaultOff_andPersists() {
        let settings = LLMTranslateSettings(defaults: UserDefaults(suiteName: "ReasoningFlagTests.\(UUID().uuidString)")!)
        XCTAssertFalse(settings.slot(.working).disableReasoning)
        settings.slot(.working).disableReasoning = true
        XCTAssertTrue(settings.slot(.working).disableReasoning)
        XCTAssertFalse(settings.slot(.strong).disableReasoning, "слоты независимы")
    }
}

/// Температура: перевод должен быть повторяемым.
final class TemperatureTests: XCTestCase {
    private func request(_ temperature: Double?) -> TranslationRequest {
        TranslationRequest(
            payload: .text("Hello"), detectedSourceLanguage: nil, targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: "translate", temperature: temperature
        )
    }

    func test_notSetByDefault_soSnapshotsStayTheSame() {
        XCTAssertNil(OpenAIRequestBodyBuilder.body(for: request(nil), model: "m")["temperature"])
        XCTAssertNil(AnthropicRequestBodyBuilder.body(for: request(nil), model: "m")["temperature"])
        XCTAssertNil((GeminiRequestBodyBuilder.body(for: request(nil))["generationConfig"] as? [String: Any])?["temperature"])
    }

    func test_zeroIsSentToAllProviders() {
        let openRouter = URL(string: "https://openrouter.ai/api/v1")!
        XCTAssertEqual(OpenAIRequestBodyBuilder.body(for: request(0), model: "openai/gpt-5.4", baseURL: openRouter)["temperature"] as? Double, 0)
        XCTAssertEqual(AnthropicRequestBodyBuilder.body(for: request(0), model: "m")["temperature"] as? Double, 0)
        XCTAssertEqual((GeminiRequestBodyBuilder.body(for: request(0))["generationConfig"] as? [String: Any])?["temperature"] as? Double, 0)
    }

    func test_directOpenAIReasoningModels_getNoTemperature() {
        let openAI = URL(string: "https://api.openai.com/v1")!
        for model in ["gpt-5.4", "gpt-5-mini", "o3", "o4-mini"] {
            XCTAssertNil(OpenAIRequestBodyBuilder.body(for: request(0), model: model, baseURL: openAI)["temperature"], model)
        }
        XCTAssertEqual(OpenAIRequestBodyBuilder.body(for: request(0), model: "gpt-4.1-mini", baseURL: openAI)["temperature"] as? Double, 0)
    }
}

/// Несколько изображений одним запросом (все листы фрагментов экрана сразу).
final class MultiImagePayloadTests: XCTestCase {
    private let request = TranslationRequest(
        payload: .images([PayloadImage(data: Data([1, 2]), mime: "image/png"), PayloadImage(data: Data([3]), mime: "image/jpeg")],
                         text: "раскладка"),
        detectedSourceLanguage: nil, targetLanguage: Locale.Language(identifier: "ru"), systemPrompt: "s"
    )

    private func userContent(_ body: [String: Any]) -> [[String: Any]] {
        let messages = body["messages"] as! [[String: Any]]
        return messages.last!["content"] as! [[String: Any]]
    }

    func test_openAI_textThenAllImages_inOrder() {
        let content = userContent(OpenAIRequestBodyBuilder.body(for: request, model: "m"))
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content[0]["text"] as? String, "раскладка")
        XCTAssertEqual((content[1]["image_url"] as? [String: String])?["url"], "data:image/png;base64,AQI=")
        XCTAssertEqual((content[2]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,Aw==")
    }

    func test_anthropic_imagesThenText() {
        let content = userContent(AnthropicRequestBodyBuilder.body(for: request, model: "m"))
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "image", "text"])
        XCTAssertEqual(((content[1]["source"] as? [String: String])?["media_type"]), "image/jpeg")
        XCTAssertEqual(content[2]["text"] as? String, "раскладка")
    }

    func test_gemini_inlineDataThenText() {
        let contents = GeminiRequestBodyBuilder.body(for: request)["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        XCTAssertEqual(parts.count, 3)
        XCTAssertNotNil(parts[0]["inline_data"])
        XCTAssertNotNil(parts[1]["inline_data"])
        XCTAssertEqual(parts[2]["text"] as? String, "раскладка")
    }

    func test_byteCount_sumsImagesAndText() {
        XCTAssertEqual(request.payload.byteCount, 3 + "раскладка".utf8.count)
    }
}
