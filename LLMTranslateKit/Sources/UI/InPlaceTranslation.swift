#if canImport(UIKit)
import UIKit

/// Вид плашек — общий для экрана «Весь экран» и картинки «Перевести на месте».
enum PlaqueStyle {
    /// Непрозрачность фона плашки: оригинал под ней просвечивает.
    static let opacity = 0.62
    /// Сдвиг плашки вниз, в высотах строки: верх исходной надписи остаётся виден.
    static let shift: CGFloat = 0.35
}

/// «Перевести на месте»: снимок → области текста → перевод листами → картинка
/// с полупрозрачными плашками поверх оригинала. Приложение не открывается:
/// картинку возвращает действие команды, а показывает «Быстрый просмотр» поверх
/// текущего приложения — после закрытия пользователь там же, где был.
public enum InPlaceTranslation {
    public struct Output: Sendable {
        public let imageData: Data
        public let regionCount: Int
        public let translatedCount: Int
    }

    public enum Failure: Error, Sendable {
        case unreadableImage
        case noTextFound
        case translation(TranslationError)
        case nothingTranslated
    }

    @MainActor
    public static func translate(imageData: Data, appGroupSuiteName: String) async throws -> Output {
        let regions = await Task.detached(priority: .userInitiated) {
            ScreenshotImageTools.detectRegions(in: imageData)
        }.value
        guard !regions.isEmpty else { throw Failure.noTextFound }

        let model = RegionOverlayModel()
        await model.start(imageData: imageData, regions: regions, appGroupSuiteName: appGroupSuiteName)
        let translations = model.translations
        if translations.isEmpty {
            if let error = model.error { throw Failure.translation(error) }
            throw Failure.nothingTranslated
        }
        let backgrounds = model.backgrounds
        let rightToLeft = model.isTargetRTL

        let rendered = await Task.detached(priority: .userInitiated) {
            PlaqueRenderer.render(
                imageData: imageData, regions: regions, translations: translations,
                backgrounds: backgrounds, rightToLeft: rightToLeft
            )
        }.value
        guard let rendered else { throw Failure.unreadableImage }
        return Output(imageData: rendered, regionCount: regions.count, translatedCount: translations.count)
    }
}

/// Рисует плашки прямо в пиксели снимка (тот же вид, что SwiftUI-плашки на
/// экране «Весь экран»): фон в тон краёв рамки, ореол у текста, сдвиг вниз,
/// шрифт от высоты строки, длинный перевод ужимается до половины.
enum PlaqueRenderer {
    static func render(
        imageData: Data,
        regions: [TextRegion],
        translations: [Int: String],
        backgrounds: [Int: RegionBackground],
        rightToLeft: Bool
    ) -> Data? {
        guard let cgImage = ScreenshotImageTools.normalizedCGImage(from: imageData) else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            for region in regions {
                guard let text = translations[region.id] else { continue }
                drawPlaque(
                    text: text, region: region, imageSize: size,
                    background: backgrounds[region.id], rightToLeft: rightToLeft, context: context.cgContext
                )
            }
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static func drawPlaque(
        text: String,
        region: TextRegion,
        imageSize: CGSize,
        background: RegionBackground?,
        rightToLeft: Bool,
        context: CGContext
    ) {
        let lineHeight = max(region.lineHeight * imageSize.height, 1)
        var rect = CGRect(
            x: region.rect.minX * imageSize.width,
            y: region.rect.minY * imageSize.height,
            width: region.rect.width * imageSize.width,
            height: region.rect.height * imageSize.height
        ).insetBy(dx: -lineHeight * 0.15, dy: -lineHeight * 0.08)
        rect.origin.y = min(rect.minY + lineHeight * PlaqueStyle.shift, imageSize.height - rect.height)

        let backgroundColor = background.map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .white
        let luminance = background.map { 0.2126 * $0.red + 0.7152 * $0.green + 0.0722 * $0.blue } ?? 1
        let textColor: UIColor = luminance > 0.55 ? .black : .white

        backgroundColor.withAlphaComponent(PlaqueStyle.opacity).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: lineHeight * 0.15).fill()

        let inner = rect.insetBy(dx: lineHeight * 0.12, dy: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        paragraph.lineBreakMode = .byWordWrapping
        func attributes(_ fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: textColor, .paragraphStyle: paragraph]
        }
        func height(_ fontSize: CGFloat) -> CGFloat {
            (text as NSString).boundingRect(
                with: CGSize(width: inner.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attributes(fontSize), context: nil
            ).height
        }
        let fullSize = max(8, lineHeight * 0.78)
        var fontSize = fullSize
        while fontSize > fullSize * 0.5, height(fontSize) > inner.height {
            fontSize *= 0.92
        }
        let textHeight = min(height(fontSize), inner.height)
        let drawRect = CGRect(x: inner.minX, y: inner.midY - textHeight / 2, width: inner.width, height: textHeight)

        // Ореол цвета фона отделяет перевод от просвечивающего оригинала.
        context.saveGState()
        context.setShadow(offset: .zero, blur: max(2, fontSize * 0.15), color: backgroundColor.withAlphaComponent(0.95).cgColor)
        for _ in 0..<2 {
            (text as NSString).draw(
                with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes(fontSize), context: nil
            )
        }
        context.restoreGState()
    }
}
#endif
