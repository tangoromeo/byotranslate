import Foundation

/// Раздел 6.1 ТЗ v1.2. `.usage` — там, где провайдер его отдаёт в ответе;
/// счётчик расхода (F15, этап 6) появится позже, форма события заводится
/// сейчас, чтобы не ломать протокол второй раз.
public enum StreamEvent: Sendable, Equatable {
    case delta(String)
    case usage(promptTokens: Int?, completionTokens: Int?)
}
