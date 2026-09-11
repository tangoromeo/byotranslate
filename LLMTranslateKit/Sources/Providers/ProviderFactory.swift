import Foundation

/// Раздел 6.1 ТЗ: единая точка конструирования любого из трёх адаптеров по
/// `ProviderID` — используется и оркестратором (`TranslationSession`), и
/// настройками (выбор модели, кнопка «Проверить»), чтобы список провайдеров
/// не дублировался в двух местах.
public enum ProviderFactory {
    public static let allProviders: [ProviderID] = [.openAICompatible, .anthropic, .googleGemini]

    public static func make(
        providerID: ProviderID,
        baseURL: URL,
        apiKey: String,
        model: String,
        firstByteTimeout: TimeInterval = 8,
        totalTimeout: TimeInterval = 30
    ) -> (any TranslationProvider)? {
        switch providerID {
        case .openAICompatible:
            return OpenAICompatibleProvider(
                baseURL: baseURL, apiKey: apiKey, model: model,
                firstByteTimeout: firstByteTimeout, totalTimeout: totalTimeout
            )
        case .anthropic:
            return AnthropicProvider(
                baseURL: baseURL, apiKey: apiKey, model: model,
                firstByteTimeout: firstByteTimeout, totalTimeout: totalTimeout
            )
        case .googleGemini:
            return GeminiProvider(
                baseURL: baseURL, apiKey: apiKey, model: model,
                firstByteTimeout: firstByteTimeout, totalTimeout: totalTimeout
            )
        default:
            return nil
        }
    }

    public static func defaultBaseURL(for providerID: ProviderID) -> URL {
        switch providerID {
        case .openAICompatible: OpenAICompatibleProvider.defaultBaseURL
        case .anthropic: AnthropicProvider.defaultBaseURL
        case .googleGemini: GeminiProvider.defaultBaseURL
        default: OpenAICompatibleProvider.defaultBaseURL
        }
    }

    public static func displayName(for providerID: ProviderID) -> String {
        switch providerID {
        case .openAICompatible: "OpenAI-совместимый"
        case .anthropic: "Anthropic"
        case .googleGemini: "Google Gemini"
        default: providerID.rawValue
        }
    }
}
