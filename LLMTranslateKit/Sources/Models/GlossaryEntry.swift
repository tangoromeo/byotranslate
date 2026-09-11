import Foundation

/// Раздел 8.1/13.3 ТЗ v1.2: пользовательский глоссарий, подставляемый в
/// системный промпт через `PromptBuilder.renderGlossarySection`. Хранится
/// как упорядоченный список, а не `[String: String]`, чтобы построчный
/// редактор мог сохранять порядок ввода и не терять запись при пустом
/// (ещё не введённом) термине.
public struct GlossaryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var term: String
    public var translation: String

    public init(id: UUID = UUID(), term: String, translation: String) {
        self.id = id
        self.term = term
        self.translation = translation
    }

    /// Раздел 8.1 ТЗ: сворачивает список в `[String: String]` для
    /// `PromptBuilder`. Строки с пустым `term` отбрасываются — это
    /// нормальное промежуточное состояние ещё не заполненной новой строки
    /// в редакторе, а не ошибка. При дублирующихся `term` побеждает
    /// последняя запись в списке.
    public static func asDictionary(_ entries: [GlossaryEntry]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }
            result[term] = entry.translation
        }
        return result
    }
}
