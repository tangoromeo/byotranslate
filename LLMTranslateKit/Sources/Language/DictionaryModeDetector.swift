import Foundation

/// Раздел 11.3 ТЗ v1.2: короткое выделение — это словарный запрос, а не
/// запрос на перевод. Чистая функция, тот же стиль, что и
/// `LanguagePairResolver` — именованные пороги + независимая проверка.
/// Действует независимо от `notesMode`, отключается отдельным тумблером
/// на уровне вызывающего кода (`dictionaryModeEnabled`), не здесь.
public enum DictionaryModeDetector {
    public static let maxWords = 4
    public static let maxCharacters = 30

    public static func shouldUseDictionaryMode(for text: String) -> Bool {
        guard text.count <= maxCharacters else { return false }
        let wordCount = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        return wordCount <= maxWords
    }
}
