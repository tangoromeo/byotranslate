import CoreGraphics
import Foundation

/// Раздел B6 бэклога: область текста на скриншоте, по которой можно тапнуть.
public struct TextRegion: Identifiable, Sendable, Equatable {
    public let id: Int
    /// Нормализованный (0...1) прямоугольник, начало координат — левый верхний
    /// угол изображения.
    public let rect: CGRect
    /// Высота одной строки внутри области, в долях высоты изображения —
    /// по ней плашке подбирается размер шрифта. По умолчанию вся область
    /// считается одной строкой.
    public let lineHeight: CGFloat

    public init(id: Int, rect: CGRect, lineHeight: CGFloat? = nil) {
        self.id = id
        self.rect = rect
        self.lineHeight = lineHeight ?? rect.height
    }
}

/// Склеивает прямоугольники текста, которые вернул детектор (слова/строки),
/// в блоки, которые пользователь воспринимает как одно целое: слова одной
/// строки → строка, соседние строки одного размера → абзац.
///
/// Чистая логика над прямоугольниками, без Vision и UIKit — тестируется на
/// синтетических данных. Работает в пикселях: нормализованные координаты
/// нельзя сравнивать между осями без учёта пропорций изображения.
public enum TextRegionGrouper {
    /// Рамки меньше этого — шум детектора, а не текст.
    static let minSide: CGFloat = 6
    /// Страховка от квадратичного взрыва на экране с сотнями мелких рамок.
    static let maxInputRects = 400

    public static func group(pixelRects: [CGRect], imageSize: CGSize) -> [TextRegion] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        let cleaned = deduplicate(pixelRects.filter { $0.width >= minSide && $0.height >= minSide })
            .prefix(maxInputRects)
        let words = cleaned.map { Item(rect: $0, lineHeight: $0.height, lineCount: 1) }
        // Высота строки — это высота склеенной строки, а не среднее по её
        // словам: слова разной высоты (иврит + латиница) тянут среднее вниз,
        // и соседние строки одного абзаца перестают склеиваться.
        let lines = merge(words, shouldMerge: belongToSameLine)
            .map { Item(rect: $0.rect, lineHeight: $0.rect.height, lineCount: 1) }
        let blocks = merge(lines, shouldMerge: belongToSameBlock)
        let ordered = blocks.sorted { lhs, rhs in
            lhs.rect.minY != rhs.rect.minY ? lhs.rect.minY < rhs.rect.minY : lhs.rect.minX < rhs.rect.minX
        }
        return ordered.enumerated().map { index, item in
            let rect = item.rect
            return TextRegion(
                id: index,
                rect: CGRect(
                    x: rect.minX / imageSize.width,
                    y: rect.minY / imageSize.height,
                    width: rect.width / imageSize.width,
                    height: rect.height / imageSize.height
                ),
                lineHeight: min(item.lineHeight, rect.height) / imageSize.height
            )
        }
    }

    /// Убирает рамки, почти целиком лежащие внутри уже взятой: детектор
    /// гоняется на нескольких масштабах, и одна и та же строка приходит
    /// несколько раз с чуть разными границами. Побеждает первая.
    static func deduplicate(_ rects: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for rect in rects {
            let isDuplicate = kept.contains { other in
                let overlap = rect.intersection(other)
                guard !overlap.isNull else { return false }
                let smaller = min(rect.width * rect.height, other.width * other.height)
                return smaller > 0 && (overlap.width * overlap.height) / smaller >= 0.7
            }
            if !isDuplicate { kept.append(rect) }
        }
        return kept
    }

    /// Прямоугольник для вырезания фрагмента из оригинала в пикселях: сама
    /// область плюс поля. Голый кроп теряет контекст (одинокое «Back»
    /// неоднозначно), а широкие поля тянут соседний текст.
    public static func cropRect(for region: TextRegion, imageSize: CGSize) -> CGRect {
        let pixel = CGRect(
            x: region.rect.minX * imageSize.width,
            y: region.rect.minY * imageSize.height,
            width: region.rect.width * imageSize.width,
            height: region.rect.height * imageSize.height
        )
        let padding = max(10, pixel.height * 0.5)
        return pixel
            .insetBy(dx: -padding, dy: -padding)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    // MARK: - Правила склейки

    /// Рамка плюс высота одной строки внутри неё. Высота блока растёт при
    /// склейке строк, а правило «шрифт почти одинаковый» должно сравнивать
    /// именно строки, иначе третья строка абзаца уже не склеится.
    struct Item {
        var rect: CGRect
        var lineHeight: CGFloat
        var lineCount: Int

        func merged(with other: Item) -> Item {
            let count = lineCount + other.lineCount
            let height = (lineHeight * CGFloat(lineCount) + other.lineHeight * CGFloat(other.lineCount)) / CGFloat(count)
            return Item(rect: rect.union(other.rect), lineHeight: height, lineCount: count)
        }
    }

    /// Слова одной строки: заметно перекрываются по вертикали, близки по
    /// горизонтали и сопоставимы по высоте.
    static func belongToSameLine(_ a: Item, _ b: Item) -> Bool {
        let overlapY = min(a.rect.maxY, b.rect.maxY) - max(a.rect.minY, b.rect.minY)
        guard overlapY / min(a.rect.height, b.rect.height) >= 0.5 else { return false }
        guard max(a.rect.height, b.rect.height) / min(a.rect.height, b.rect.height) <= 2 else { return false }
        let gapX = max(0, max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX))
        return gapX <= max(a.rect.height, b.rect.height)
    }

    /// Строки одного абзаца: почти одинаковая высота шрифта, небольшой
    /// промежуток по вертикали и общая зона по горизонтали (выравнивание
    /// слева или справа — для иврита и арабского).
    static func belongToSameBlock(_ a: Item, _ b: Item) -> Bool {
        let shortest = min(a.lineHeight, b.lineHeight)
        guard max(a.lineHeight, b.lineHeight) / shortest <= 1.6 else { return false }
        let (top, bottom) = a.rect.minY <= b.rect.minY ? (a.rect, b.rect) : (b.rect, a.rect)
        guard bottom.minY - top.maxY <= shortest * 0.8 else { return false }
        let overlapX = min(a.rect.maxX, b.rect.maxX) - max(a.rect.minX, b.rect.minX)
        return overlapX >= 0.3 * min(a.rect.width, b.rect.width)
    }

    private static func merge(_ input: [Item], shouldMerge: (Item, Item) -> Bool) -> [Item] {
        var items = input
        var changed = true
        while changed {
            changed = false
            search: for i in items.indices {
                for j in items.indices where j > i {
                    if shouldMerge(items[i], items[j]) {
                        items[i] = items[i].merged(with: items[j])
                        items.remove(at: j)
                        changed = true
                        break search
                    }
                }
            }
        }
        return items
    }
}
