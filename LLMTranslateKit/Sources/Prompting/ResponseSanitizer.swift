import Foundation

/// Раздел 8.4 ТЗ: модели регулярно нарушают инструкцию «только перевод».
/// Чистая функция, юнит-тесты — раздел 14, п. 1 ТЗ.
public enum ResponseSanitizer {
    /// Регистронезависимо, только в начале строки — раздел 8.4 ТЗ.
    private static let leadingPrefixes = [
        "вот перевод:",
        "перевод:",
        "translation:",
        "на изображении:",
    ]

    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""),
        ("«", "»"),
        ("\u{201C}", "\u{201D}"),
    ]

    public static func sanitize(_ response: String, original: String) -> String {
        var text = response
        text = trimEmptyLines(text)
        text = stripLeadingPrefix(text)
        text = trimEmptyLines(text)
        text = stripWrappingCodeFence(text, original: original)
        text = trimEmptyLines(text)
        text = stripWrappingQuotes(text, original: original)
        text = trimEmptyLines(text)
        return text
    }

    private static func stripLeadingPrefix(_ text: String) -> String {
        let lowercased = text.lowercased()
        for prefix in leadingPrefixes where lowercased.hasPrefix(prefix) {
            let dropped = text.dropFirst(prefix.count)
            return String(dropped).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func stripWrappingQuotes(_ text: String, original: String) -> String {
        for pair in quotePairs {
            guard text.count >= 2, text.first == pair.open, text.last == pair.close else { continue }
            let originalHasSameWrap = original.first == pair.open && original.last == pair.close
            guard !originalHasSameWrap else { continue }
            return String(text.dropFirst().dropLast())
        }
        return text
    }

    private static func stripWrappingCodeFence(_ text: String, original: String) -> String {
        let fence = "```"
        guard text.hasPrefix(fence), text.hasSuffix(fence), text.count >= fence.count * 2 else { return text }
        let originalHasFence = original.hasPrefix(fence) && original.hasSuffix(fence)
        guard !originalHasFence else { return text }

        var inner = Substring(text.dropFirst(fence.count).dropLast(fence.count))
        // Необязательный языковой тег сразу после открывающего ```, например ```text\n...
        if let newlineIndex = inner.firstIndex(of: "\n") {
            let firstLine = inner[inner.startIndex..<newlineIndex]
            if !firstLine.isEmpty, !firstLine.contains(where: \.isWhitespace), firstLine.count < 20 {
                inner = inner[inner.index(after: newlineIndex)...]
            }
        }
        return String(inner)
    }

    private static func trimEmptyLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
