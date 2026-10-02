import CoreGraphics
import Foundation
import Vision

/// Раздел B6 бэклога: где на изображении лежит текст — без чтения самого
/// текста. `VNDetectTextRectanglesRequest` ищет текстовые области и не
/// зависит от языка (проверено на ивритской картинке), в отличие от
/// `VNRecognizeTextRequest`, который иврит не поддерживает. Читает и
/// переводит фрагменты уже мультимодальная модель.
///
/// Детектор нестабилен по масштабу: на меню банковского приложения (15
/// строк иврита) один проход в исходном размере пропустил строку
/// «צפייה בקוד סודי» стабильно, а проход при увеличении 1.5× её нашёл;
/// объединение проходов на нескольких масштабах покрыло все 15 строк.
/// Поэтому гоняем несколько масштабов и склеиваем результат.
///
/// Синхронный и тяжёлый — вызывать вне главного потока.
public enum TextRegionDetector {
    /// 1.0 обязателен; остальные дают шанс найти пропущенное. Какие масштабы
    /// сработают, заранее не предсказать: на мак-кадре 1188×2576 строку нашёл
    /// только 1.5×. Весь набор из семи проходов на телефоне занимает около
    /// 0.4 с.
    static let scales: [CGFloat] = [1, 0.75, 1.25, 1.5, 1.75, 2, 0.5]

    /// Потолок на один увеличенный проход, в пикселях (RGBA = 4 байта на
    /// пиксель). У расширений («Поделиться») жёсткий лимит памяти на весь
    /// процесс, у приложения — на порядок свободнее; фото на 12 Мп без этого
    /// порождало бы растр в 108 МБ на проход 2×.
    static var maxScaledPixels: Double {
        Bundle.main.bundlePath.hasSuffix(".appex") ? 9_000_000 : 30_000_000
    }

    /// Какие масштабы можно прогнать для изображения такого размера. 1.0
    /// всегда в списке: без него детектор не работает вообще.
    static func usableScales(for size: CGSize, budget: Double) -> [CGFloat] {
        scales.filter { $0 == 1 || size.width * $0 * size.height * $0 <= budget }
    }

    public static func detectRegions(in image: CGImage) throws -> [TextRegion] {
        let size = CGSize(width: image.width, height: image.height)
        var rects: [CGRect] = []
        for scale in usableScales(for: size, budget: maxScaledPixels) {
            guard let scaled = scale == 1 ? image : resized(image, by: scale) else { continue }
            let pass = try detectRects(in: scaled)
            // Обратно в пиксели исходного изображения.
            rects += pass.map { CGRect(x: $0.minX / scale, y: $0.minY / scale, width: $0.width / scale, height: $0.height / scale) }
        }
        return TextRegionGrouper.group(pixelRects: rects, imageSize: size)
    }

    private static func detectRects(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).map { observation -> CGRect in
            // Vision отдаёт нормализованные координаты с началом внизу слева.
            let box = observation.boundingBox
            return CGRect(
                x: box.minX * size.width,
                y: (1 - box.maxY) * size.height,
                width: box.width * size.width,
                height: box.height * size.height
            )
        }
    }

    private static func resized(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
