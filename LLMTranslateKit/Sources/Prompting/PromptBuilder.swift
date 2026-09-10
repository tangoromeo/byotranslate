import Foundation

/// Раздел 8 ТЗ — системные промпты по умолчанию и подстановка глоссария.
public enum PromptBuilder {
    /// Раздел 8.1 ТЗ.
    public static let defaultTextSystemPrompt = """
    Ты — переводчик. Переведи текст пользователя на {targetLanguage}.

    Правила:
    - Выводи ТОЛЬКО перевод. Никаких пояснений, преамбул, извинений, кавычек вокруг результата.
    - Сохраняй регистр, пунктуацию, переносы строк и разметку исходника.
    - Сохраняй без перевода: имена собственные, названия компаний и продуктов,
      идентификаторы, код, URL, email, числа, единицы измерения.
    - Если текст — фрагмент без контекста, переводи его как фрагмент,
      не достраивай предложение.
    {glossarySection}
    """

    /// Раздел 8.2 ТЗ.
    public static let defaultImageSystemPrompt = """
    На изображении — снимок экрана или фотография текста.
    Извлеки весь текст и переведи его на {targetLanguage}.

    Правила:
    - Выводи ТОЛЬКО перевод, без описания изображения и без комментариев.
    - Сохраняй структуру: абзацы, списки, таблицы, порядок блоков сверху вниз.
    - Интерфейсные элементы (кнопки, пункты меню, поля) выводи отдельными строками
      в том порядке, в котором они расположены.
    - Не переводи: имена собственные, названия компаний и продуктов, URL, email,
      номера счетов, идентификаторы, числа.
    - Нечитаемый фрагмент помечай как [неразборчиво], не додумывай.
    {glossarySection}
    """

    /// Раздел 8.1 ТЗ: `{glossarySection}` подставляется только при непустом глоссарии.
    public static func render(
        template: String,
        targetLanguage: Locale.Language,
        glossary: [String: String]
    ) -> String {
        let languageName = languageDisplayName(targetLanguage)
        let glossarySection = renderGlossarySection(glossary)
        return template
            .replacingOccurrences(of: "{targetLanguage}", with: languageName)
            .replacingOccurrences(of: "{glossarySection}", with: glossarySection)
    }

    private static func renderGlossarySection(_ glossary: [String: String]) -> String {
        guard !glossary.isEmpty else { return "" }
        let lines = glossary
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "  \($0.key) → \($0.value)" }
            .joined(separator: "\n")
        return "- Обязательная терминология (используй строго эти соответствия):\n\(lines)"
    }

    private static func languageDisplayName(_ language: Locale.Language) -> String {
        Locale(identifier: "ru").localizedString(forLanguageCode: language.languageCode?.identifier ?? language.minimalIdentifier)
            ?? language.minimalIdentifier
    }
}
