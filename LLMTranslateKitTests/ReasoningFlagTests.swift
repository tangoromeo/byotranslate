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
