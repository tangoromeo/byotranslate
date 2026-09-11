import Foundation

/// Раздел 10.7 ТЗ: чистая геометрия даунскейла — не зависит от `UIImage`,
/// чтобы быть тестируемой (раздел 14, п. 6 ТЗ).
public enum ImageResizeMath {
    /// Новый размер, вписанный в `maxLongSide` по длинной стороне, с
    /// сохранением пропорций. Не увеличивает изображение, если оно уже
    /// меньше предела.
    public static func targetSize(
        originalWidth: Double,
        originalHeight: Double,
        maxLongSide: Double
    ) -> (width: Int, height: Int) {
        guard originalWidth > 0, originalHeight > 0, maxLongSide > 0 else {
            return (max(0, Int(originalWidth.rounded())), max(0, Int(originalHeight.rounded())))
        }
        let longSide = max(originalWidth, originalHeight)
        guard longSide > maxLongSide else {
            return (Int(originalWidth.rounded()), Int(originalHeight.rounded()))
        }
        let scale = maxLongSide / longSide
        return (
            max(1, Int((originalWidth * scale).rounded())),
            max(1, Int((originalHeight * scale).rounded()))
        )
    }
}

/// Раздел 10.7 ТЗ: «Превышение — понижать качество ступенчато до 0.5,
/// затем разрешение до 1024 px, затем ошибка». Порядок шагов и выбор
/// первого подходящего — чистая функция, тестируется без реального
/// кодирования JPEG (см. `ImagePreparation` для интеграции).
public enum ImageQualityLadder {
    public struct Step: Sendable, Equatable {
        public let maxLongSide: Double
        public let jpegQuality: Double

        public init(maxLongSide: Double, jpegQuality: Double) {
            self.maxLongSide = maxLongSide
            self.jpegQuality = jpegQuality
        }
    }

    public static let defaultMaxLongSide: Double = 1568
    public static let steppedDownQuality: Double = 0.5
    public static let steppedDownLongSide: Double = 1024

    public static let steps: [Step] = [
        Step(maxLongSide: defaultMaxLongSide, jpegQuality: 0.8),
        Step(maxLongSide: defaultMaxLongSide, jpegQuality: steppedDownQuality),
        Step(maxLongSide: steppedDownLongSide, jpegQuality: steppedDownQuality),
    ]

    /// Индекс первого шага, чей размер (переданный вызывающим кодом после
    /// реального кодирования) укладывается в `limitBytes`. `nil`, если
    /// `byteCounts` короче `steps` (шаг ещё не попробован).
    public static func firstFittingStepIndex(byteCounts: [Int], limitBytes: Int) -> Int? {
        byteCounts.firstIndex { $0 <= limitBytes }
    }
}
