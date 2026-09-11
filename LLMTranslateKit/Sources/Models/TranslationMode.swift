import Foundation

/// Раздел 8.1 ТЗ v1.2.
public enum TranslationMode: Sendable, Equatable, Codable {
    /// Только перевод. Режим по умолчанию для любого входа.
    case plain
    /// Перевод плюс комментарии модели после маркера `⟦NOTES⟧`.
    case withNotes
    /// Словарная статья для короткого выделения (раздел 11.3 ТЗ).
    case dictionary
}
