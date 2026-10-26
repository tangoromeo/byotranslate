import CoreGraphics

/// Раскладка переводов на картинке «на месте»: сколько места есть у каждой
/// подписи, чтобы перевод (обычно длиннее иврита) не налезал на соседние
/// надписи. Чистая геометрия без UIKit — тестируется в SPM-харнессе.
public enum PlaqueLayout {
    /// Свободный прямоугольник вокруг `rects[index]`: влево и вправо — до соседей
    /// в той же строке (пересекающихся по вертикали), вверх и вниз — до соседей,
    /// перекрывающихся по горизонтали; промежуток между соседями делится пополам,
    /// всё в пределах `bounds` и с зазором `gap`.
    /// Соседи, которые уже пересекаются с самой областью, не ограничивают её
    /// (иначе свободное место схлопнулось бы).
    public static func freeSpace(for index: Int, in rects: [CGRect], bounds: CGRect, gap: CGFloat) -> CGRect {
        let own = rects[index]
        var left = bounds.minX
        var right = bounds.maxX
        var top = bounds.minY
        var bottom = bounds.maxY

        for (other, rect) in rects.enumerated() where other != index && !rect.intersects(own) {
            let sharesRow = rect.maxY > own.minY && rect.minY < own.maxY
            let sharesColumn = rect.maxX > own.minX && rect.minX < own.maxX
            // Зазор между соседями делится пополам: иначе обе подписи
            // претендуют на него целиком и наезжают друг на друга.
            if sharesRow {
                if rect.maxX <= own.minX { left = max(left, (rect.maxX + own.minX) / 2 + gap / 2) }
                if rect.minX >= own.maxX { right = min(right, (own.maxX + rect.minX) / 2 - gap / 2) }
            } else if sharesColumn {
                if rect.maxY <= own.minY { top = max(top, (rect.maxY + own.minY) / 2 + gap / 2) }
                if rect.minY >= own.maxY { bottom = min(bottom, (own.maxY + rect.minY) / 2 - gap / 2) }
            }
        }
        // Своя область всегда внутри свободного места.
        left = min(left, own.minX)
        right = max(right, own.maxX)
        top = min(top, own.minY)
        bottom = max(bottom, own.maxY)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Прямоугольник размера `size` с центром как можно ближе к `center`, но
    /// внутри `space` (если не помещается — прижат к левому/верхнему краю).
    public static func place(_ size: CGSize, near center: CGPoint, in space: CGRect) -> CGRect {
        let x = min(max(center.x - size.width / 2, space.minX), max(space.minX, space.maxX - size.width))
        let y = min(max(center.y - size.height / 2, space.minY), max(space.minY, space.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
