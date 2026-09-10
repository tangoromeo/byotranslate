import Foundation

/// Раздел 6.4, п. 2 ТЗ: список моделей для выпадающего меню, если API его отдаёт.
public struct ModelDescriptor: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { rawID }
    public let rawID: String
    public let displayName: String?

    public init(rawID: String, displayName: String? = nil) {
        self.rawID = rawID
        self.displayName = displayName
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
