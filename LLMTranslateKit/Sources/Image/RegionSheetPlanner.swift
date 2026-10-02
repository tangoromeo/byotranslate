import CoreGraphics
import Foundation

/// Раздел B6, этап 3: фрагменты скриншота склеиваются в «листы» — картинки
/// из нескольких кропов друг под другом, каждый с номером слева. Один запрос
/// на лист вместо запроса на фрагмент; кропы идут в полном разрешении, а не
/// ужатым общим кадром, и ничего не закрывают рамками.
///
/// Здесь только геометрия (чистая функция, тестируется без UIKit);
/// рисование листа — `RegionSheetRenderer`.
public enum RegionSheetPlanner {
    public struct Row: Sendable, Equatable {
        /// Индекс фрагмента во входном массиве.
        public let index: Int
        /// Где кроп лежит на листе.
        public let frame: CGRect
    }

    public struct Sheet: Sendable, Equatable {
        public let size: CGSize
        public let rows: [Row]
    }

    /// Ширина колонки с номером.
    public static let labelWidth: CGFloat = 72
    public static let padding: CGFloat = 12
    public static let rowGap: CGFloat = 16
    /// Кроп шире этого уменьшается; уже — остаётся как есть (не растягиваем).
    public static let maxCropWidth: CGFloat = 760
    /// Лист должен укладываться в длинную сторону, которую `ImagePreparation`
    /// не пережимает (1568): иначе мелкий текст смазывается второй раз.
    public static let maxSheetHeight: CGFloat = 1500
    public static let maxRowsPerSheet = 12
    /// Страховка от запроса на сотню фрагментов: дальше — только то, что влезло.
    public static let maxSheets = 4

    public static func plan(cropSizes: [CGSize]) -> [Sheet] {
        var sheets: [Sheet] = []
        var rows: [Row] = []
        var y = padding
        var width: CGFloat = 0

        func closeSheet() {
            guard !rows.isEmpty else { return }
            sheets.append(Sheet(size: CGSize(width: width + padding, height: y), rows: rows))
            rows = []
            y = padding
            width = 0
        }

        for (index, original) in cropSizes.enumerated() where original.width > 0 && original.height > 0 {
            var size = original
            let maxHeight = maxSheetHeight - 2 * padding
            let scale = min(1, maxCropWidth / size.width, maxHeight / size.height)
            size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

            let needed = size.height + (rows.isEmpty ? 0 : rowGap)
            if !rows.isEmpty, y + needed + padding > maxSheetHeight || rows.count >= maxRowsPerSheet {
                closeSheet()
                if sheets.count >= maxSheets { return sheets }
            }
            if !rows.isEmpty { y += rowGap }
            let frame = CGRect(x: padding + labelWidth, y: y, width: size.width, height: size.height)
            rows.append(Row(index: index, frame: frame))
            y += size.height
            width = max(width, frame.maxX)
        }
        closeSheet()
        return Array(sheets.prefix(maxSheets))
    }
}
