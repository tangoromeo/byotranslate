import Foundation

/// Раздел 6.4, п. 2 ТЗ: список моделей для выпадающего меню, если API его отдаёт.
///
/// `supportsImages` — там, где провайдер сам публикует модальности модели
/// (например, OpenRouter отдаёт `architecture.input_modalities` в
/// `/models`), не нужно заставлять пользователя вручную гадать и щёлкать
/// тумблер «модель понимает изображения» — источник истины есть в самом
/// списке. `nil`, если провайдер такой информации не даёт (обычный OpenAI
/// API, Ollama, LM Studio) — тогда решает пользователь вручную.
public struct ModelDescriptor: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { rawID }
    public let rawID: String
    public let displayName: String?
    public let supportsImages: Bool?

    public init(rawID: String, displayName: String? = nil, supportsImages: Bool? = nil) {
        self.rawID = rawID
        self.displayName = displayName
        self.supportsImages = supportsImages
    }
}

/// Результат `TranslationProvider.validate()` — раздел 12, экран 2 ТЗ
/// («Проверить» → тестовый перевод "Hello, world").
public struct ProviderCapabilities: Sendable, Equatable {
    public let modelID: String
    public let supportsImages: Bool

    public init(modelID: String, supportsImages: Bool) {
        self.modelID = modelID
        self.supportsImages = supportsImages
    }
}
