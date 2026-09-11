import Foundation

/// Раздел 11.3 ТЗ v1.2: словарный режим (если включён) всегда побеждает на
/// коротком тексте — он специфичнее и уже сам включает варианты/пояснения.
/// `notesMode` применяется только когда словарный режим не сработал.
public enum TranslationModeResolver {
    public static func resolve(text: String, dictionaryModeEnabled: Bool, notesMode: NotesMode) -> TranslationMode {
        let isShort = DictionaryModeDetector.shouldUseDictionaryMode(for: text)
        if dictionaryModeEnabled, isShort {
            return .dictionary
        }
        switch notesMode {
        case .always:
            return .withNotes
        case .shortOnly:
            return isShort ? .withNotes : .plain
        case .off:
            return .plain
        }
    }
}
