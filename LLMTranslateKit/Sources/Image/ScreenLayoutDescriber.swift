import CoreGraphics

/// Раскладка экрана текстом для модели: где каждый фрагмент и чем он, скорее
/// всего, является (заголовок, пункт списка, кнопка). Даёт контекст экрана без
/// отправки самого скриншота — всё из геометрии, которую уже нашёл Vision.
/// Чистая функция, тестируется в SPM-харнессе.
public enum ScreenLayoutDescriber {
    public struct Item: Sendable, Equatable {
        /// Номер фрагмента, под которым он стоит на листе (id + 1).
        public let number: Int
        /// Нормализованный прямоугольник (0…1, начало — верхний левый угол).
        public let rect: CGRect
        /// Высота строки в долях высоты снимка.
        public let lineHeight: CGFloat
        /// Фон под надписью заметно отличается от фона страницы (кнопка, плашка).
        public let onColoredBackground: Bool

        public init(number: Int, rect: CGRect, lineHeight: CGFloat, onColoredBackground: Bool = false) {
            self.number = number
            self.rect = rect
            self.lineHeight = lineHeight
            self.onColoredBackground = onColoredBackground
        }
    }

    /// Строки вида «3: вверху, по центру, крупный шрифт» и «5–9: список одинаковых
    /// пунктов, слева», сверху вниз.
    public static func describe(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "" }
        let ordered = items.sorted { lhs, rhs in
            abs(lhs.rect.minY - rhs.rect.minY) > 0.005 ? lhs.rect.minY < rhs.rect.minY : lhs.rect.minX < rhs.rect.minX
        }
        let heights = ordered.map(\.lineHeight).sorted()
        let typical = heights[heights.count / 2]

        var lines: [String] = []
        var index = 0
        while index < ordered.count {
            // Список: подряд ≥3 фрагмента с общим левым краем и одинаковым шрифтом, друг под другом.
            var end = index
            while end + 1 < ordered.count, isNextListItem(ordered[end], ordered[end + 1]) { end += 1 }
            if end - index + 1 >= 3 {
                let first = ordered[index], last = ordered[end]
                let numbers = ordered[index...end].map(\.number)
                let label = numbers == Array(first.number...last.number)
                    ? "\(first.number)–\(last.number)"
                    : numbers.map(String.init).joined(separator: ", ")
                lines.append("\(label): список однотипных пунктов, \(horizontal(first.rect)), \(vertical(first.rect))")
                index = end + 1
                continue
            }
            lines.append("\(ordered[index].number): " + describe(ordered[index], typical: typical))
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ item: Item, typical: CGFloat) -> String {
        var parts = [vertical(item.rect), horizontal(item.rect)]
        if item.lineHeight >= typical * 1.4 {
            parts.append("крупный шрифт")
        } else if item.lineHeight <= typical * 0.75 {
            parts.append("мелкий шрифт")
        }
        if item.rect.height > item.lineHeight * 1.6 {
            parts.append("несколько строк")
        }
        if item.onColoredBackground {
            parts.append("на цветной плашке (похоже на кнопку)")
        }
        return parts.joined(separator: ", ")
    }

    private static func isNextListItem(_ a: Item, _ b: Item) -> Bool {
        guard abs(a.rect.minX - b.rect.minX) < 0.03 || abs(a.rect.maxX - b.rect.maxX) < 0.03 else { return false }
        guard max(a.lineHeight, b.lineHeight) / max(min(a.lineHeight, b.lineHeight), 0.0001) <= 1.2 else { return false }
        let gap = b.rect.minY - a.rect.maxY
        return gap >= -0.002 && gap <= 0.12
    }

    private static func vertical(_ rect: CGRect) -> String {
        if rect.midY < 0.2 { return "вверху" }
        if rect.midY > 0.8 { return "внизу" }
        return "в середине"
    }

    private static func horizontal(_ rect: CGRect) -> String {
        if rect.width > 0.6 { return "во всю ширину" }
        if rect.midX < 0.38 { return "слева" }
        if rect.midX > 0.62 { return "справа" }
        return "по центру"
    }
}
