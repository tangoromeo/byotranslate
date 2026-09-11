import Foundation

/// Раздел 6.1 ТЗ. Текст и изображение проходят через один и тот же протокол.
public enum Payload: Sendable, Equatable {
    case text(String)
    case image(Data, mime: String)
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

    public init(
        payload: Payload,
        detectedSourceLanguage: Locale.Language?,
        targetLanguage: Locale.Language,
        mode: TranslationMode = .plain,
        systemPrompt: String,
        glossary: [String: String] = [:],
        maxOutputTokens: Int = 2048
    ) {
        self.payload = payload
        self.detectedSourceLanguage = detectedSourceLanguage
        self.targetLanguage = targetLanguage
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.glossary = glossary
        self.maxOutputTokens = maxOutputTokens
    }
}
