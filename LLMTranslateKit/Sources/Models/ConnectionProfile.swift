import Foundation

/// Раздел B5: шаблон подключения. Пресет подставляет тип API и адрес, чтобы
/// пользователю оставалось вставить только ключ.
public enum ProfilePreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic
    case google
    case openRouter
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    /// `nil` у `custom`: тип API выбирает пользователь.
    public var providerID: ProviderID? {
        switch self {
        case .openAI, .openRouter: .openAICompatible
        case .anthropic: .anthropic
        case .google: .googleGemini
        case .custom: nil
        }
    }

    /// `nil` у `custom`: адрес вводит пользователь.
    public var defaultBaseURL: URL? {
        switch self {
        case .openAI: OpenAICompatibleProvider.defaultBaseURL
        case .anthropic: AnthropicProvider.defaultBaseURL
        case .google: GeminiProvider.defaultBaseURL
        case .openRouter: URL(string: "https://openrouter.ai/api/v1")
        case .custom: nil
        }
    }

    /// Какой пресет соответствует уже настроенному вручную слоту (миграция).
    public static func infer(providerID: ProviderID, baseURL: URL) -> ProfilePreset {
        let host = baseURL.host?.lowercased() ?? ""
        if host.hasSuffix("openrouter.ai") { return .openRouter }
        switch providerID {
        case .openAICompatible where host == "api.openai.com": return .openAI
        case .anthropic where host == "api.anthropic.com": return .anthropic
        case .googleGemini where host == "generativelanguage.googleapis.com": return .google
        default: return .custom
        }
    }
}

/// Подключение к провайдеру: тип API, адрес и (в Keychain, по `id`) ключ.
/// Слоты `working`/`strong` ссылаются на профиль и добавляют к нему модель.
public struct ConnectionProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var preset: ProfilePreset
    public var providerID: ProviderID
    public var baseURL: URL

    public init(id: UUID = UUID(), preset: ProfilePreset, providerID: ProviderID, baseURL: URL) {
        self.id = id
        self.preset = preset
        self.providerID = providerID
        self.baseURL = baseURL
    }

    /// Профиль из пресета; для `custom` тип API и адрес обязательны.
    public static func make(preset: ProfilePreset, providerID: ProviderID? = nil, baseURL: URL? = nil) -> ConnectionProfile? {
        guard let providerID = preset.providerID ?? providerID,
              let baseURL = preset.defaultBaseURL ?? baseURL
        else { return nil }
        return ConnectionProfile(preset: preset, providerID: providerID, baseURL: baseURL)
    }

    public var displayName: String { preset.displayName }
}

/// Что реально нужно слоту, чтобы сходить в сеть.
public struct ResolvedConnection: Sendable {
    public let providerID: ProviderID
    public let baseURL: URL
    public let apiKey: String?

    public init(providerID: ProviderID, baseURL: URL, apiKey: String?) {
        self.providerID = providerID
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}
