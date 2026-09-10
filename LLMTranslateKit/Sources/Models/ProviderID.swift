import Foundation

/// Идентификатор LLM-провайдера. Раздел 6.1 ТЗ.
public struct ProviderID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// OpenAI-совместимый адаптер (раздел 6.2/6.3 ТЗ) — реализован в этапе 1.
    public static let openAICompatible = ProviderID(rawValue: "openai-compatible")
    /// Реализуется в этапе 2.
    public static let anthropic = ProviderID(rawValue: "anthropic")
    /// Реализуется в этапе 2.
    public static let googleGemini = ProviderID(rawValue: "google-gemini")
}
