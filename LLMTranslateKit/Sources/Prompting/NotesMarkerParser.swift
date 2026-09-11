import Foundation

/// Раздел 8.7 ТЗ v1.2: разбор потока по маркеру `⟦NOTES⟧`, отделяющему
/// перевод от комментариев модели. Тот же приём, что и `SSELineAssembler`
/// (хвостовой буфер непереданных символов), но по строкам текста, не по
/// байтам: маркер может прийти разорванным между дельтами стрима.
public struct NotesMarkerParser: Sendable {
    public static let marker = "⟦NOTES⟧"

    /// Хвост, который мог бы оказаться началом маркера — придерживаем его,
    /// пока не станет ясно, что это либо маркер, либо обычный текст.
    private var pendingTail = ""
    private var markerFound = false

    public init() {}

    /// Раздел 8.7, п. 1 ТЗ: разбор потоковый — всё, что пришло до маркера,
    /// немедленно возвращается как перевод.
    public mutating func feed(_ delta: String) -> (translation: String, notes: String) {
        guard !markerFound else {
            return ("", delta)
        }

        let combined = pendingTail + delta
        guard let range = combined.range(of: Self.marker) else {
            // Маркера целиком нет — но хвост длиной до marker.count - 1
            // символов может быть его началом, не отдаём его пока в перевод.
            let holdCount = min(combined.count, Self.marker.count - 1)
            let splitIndex = combined.index(combined.endIndex, offsetBy: -holdCount)
            let safeToEmit = String(combined[combined.startIndex..<splitIndex])
            pendingTail = String(combined[splitIndex...])
            return (safeToEmit, "")
        }

        markerFound = true
        let translation = String(combined[combined.startIndex..<range.lowerBound])
        let notes = String(combined[range.upperBound...])
        pendingTail = ""
        return (translation, notes)
    }

    /// Раздел 8.7, п. 4 ТЗ: маркер так и не пришёл — весь придержанный хвост
    /// на самом деле обычный текст, отдаём его как перевод.
    public mutating func finish() -> (translation: String, notes: String) {
        guard !markerFound else { return ("", "") }
        let leftover = pendingTail
        pendingTail = ""
        return (leftover, "")
    }
}
