import Foundation

/// Раздел 6.1 ТЗ. Текст и изображение проходят через один и тот же протокол.
public enum Payload: Sendable, Equatable {
    case text(String)
    case image(Data, mime: String)
    /// Несколько изображений одним сообщением плюс текст к ним — для перевода
    /// всех фрагментов экрана одним запросом с раскладкой экрана в тексте.
    case images([PayloadImage], text: String)
}

public struct PayloadImage: Sendable, Equatable {
    public let data: Data
    public let mime: String

    public init(data: Data, mime: String) {
        self.data = data
        self.mime = mime
    }
}

extension Payload {
    /// Размер полезной нагрузки в байтах (для журнала запросов).
    public var byteCount: Int {
        switch self {
        case let .text(text): text.utf8.count
        case let .image(data, _): data.count
        case let .images(images, text): images.reduce(text.utf8.count) { $0 + $1.data.count }
        }
    }
}

public struct TranslationRequest: Sendable {
    public let payload: Payload
    /// `nil`, если язык источника не определён (раздел 7, п. 5 ТЗ).
    public let detectedSourceLanguage: Locale.Language?
    public let targetLanguage: Locale.Language
    /// Раздел 8.1 ТЗ v1.2 — влияет на то, какой шаблон промпта и какой
    /// парсинг ответа (маркер `⟦NOTES⟧`) применяются выше по стеку.
    public let mode: TranslationMode
    public let systemPrompt: String
    /// Термин → перевод. Может быть пустым.
    public let glossary: [String: String]
    public let maxOutputTokens: Int
    /// Просить провайдера не «размышлять» перед ответом. Сейчас поддержано
    /// только для OpenRouter (единый параметр `reasoning.enabled`); остальные
    /// провайдеры флаг игнорируют. Размышляющие модели с лимитом ответа
    /// приложения могут отдать пустой ответ: всё уходит на рассуждения.
    public let disableReasoning: Bool
    /// Температура генерации. `nil` — не отправлять (умолчание провайдера).
    /// Перевод выставляет 0: с умолчанием (обычно 1) один и тот же снимок
    /// переводился по-разному.
    public let temperature: Double?

    public init(
        payload: Payload,
        detectedSourceLanguage: Locale.Language?,
        targetLanguage: Locale.Language,
        mode: TranslationMode = .plain,
        systemPrompt: String,
        glossary: [String: String] = [:],
        maxOutputTokens: Int = 2048,
        disableReasoning: Bool = false,
        temperature: Double? = nil
    ) {
        self.payload = payload
        self.detectedSourceLanguage = detectedSourceLanguage
        self.targetLanguage = targetLanguage
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.glossary = glossary
        self.maxOutputTokens = maxOutputTokens
        self.disableReasoning = disableReasoning
        self.temperature = temperature
    }
}
