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
        removeDebugArtifacts(appGroupSuiteName: appGroupSuiteName)

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

/// Разовая чистка: отладочные сборки сохраняли снимки и кропы для разбора
/// промахов кэша в Library/Caches App Group. Сейчас они не пишутся; удаляем остатки.
private func removeDebugArtifacts(appGroupSuiteName: String) {
    guard let caches = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
        .appendingPathComponent("Library/Caches", isDirectory: true),
          let names = try? FileManager.default.contentsOfDirectory(atPath: caches.path) else { return }
    for name in names where name.hasPrefix("full-") || name.hasPrefix("miss-") {
        try? FileManager.default.removeItem(at: caches.appendingPathComponent(name))
    }
}

/// Рисует перевод прямо в пиксели снимка, как переводчик Google: без
/// прямоугольника-плашки — исходный текст затирается цветом фона под ним (у
/// красной кнопки — красным), поверх пишется перевод. Форма кнопок, рамки и фон
/// остаются оригинальными. Каждый перевод занимает только своё свободное место
/// (`PlaqueLayout`), поэтому соседние подписи не наезжают друг на друга.
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
        let translated = regions.filter { translations[$0.id] != nil }
        let pixelRects = translated.map { pixelRect($0, in: size) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            // Сначала затираем все исходные надписи, потом пишем переводы:
            // иначе затирка следующей подписи могла бы съесть уже написанный текст.
            for (region, rect) in zip(translated, pixelRects) {
                let lineHeight = max(region.lineHeight * size.height, 1)
                color(backgrounds[region.id]).setFill()
                UIBezierPath(
                    roundedRect: rect.insetBy(dx: -lineHeight * 0.12, dy: -lineHeight * 0.1),
                    cornerRadius: lineHeight * 0.15
                ).fill()
            }
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.02, dy: 0)
            for (index, region) in translated.enumerated() {
                guard let text = translations[region.id] else { continue }
                let space = PlaqueLayout.freeSpace(for: index, in: pixelRects, bounds: bounds, gap: size.width * 0.01)
                drawText(
                    text, source: pixelRects[index], space: space, lineHeight: max(region.lineHeight * size.height, 1),
                    imageWidth: size.width, background: backgrounds[region.id], rightToLeft: rightToLeft,
                    context: context.cgContext
                )
            }
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static func pixelRect(_ region: TextRegion, in size: CGSize) -> CGRect {
        CGRect(
            x: region.rect.minX * size.width,
            y: region.rect.minY * size.height,
            width: region.rect.width * size.width,
            height: region.rect.height * size.height
        )
    }

    private static func color(_ background: RegionBackground?) -> UIColor {
        background.map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .white
    }

    private static func drawText(
        _ text: String,
        source: CGRect,
        space: CGRect,
        lineHeight: CGFloat,
        imageWidth: CGFloat,
        background: RegionBackground?,
        rightToLeft: Bool,
        context: CGContext
    ) {
        let backgroundColor = color(background)
        let luminance = background.map { 0.2126 * $0.red + 0.7152 * $0.green + 0.0722 * $0.blue } ?? 1
        let textColor: UIColor = luminance > 0.55 ? .black : .white

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
        paragraph.lineBreakMode = .byWordWrapping
        func attributes(_ fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: textColor, .paragraphStyle: paragraph]
        }
        func measure(_ fontSize: CGFloat, width: CGFloat) -> CGSize {
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attributes(fontSize), context: nil
            )
            return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        }

        // Шрифт — от высоты строки оригинала, но не мельче читаемого минимума
        // (снимок в «Быстром просмотре» показывается примерно в треть размера).
        let minimumFont = imageWidth * 0.028
        var fontSize = max(lineHeight * 0.8, minimumFont)
        // Сначала в одну строку в пределах свободного места, потом перенос,
        // потом уменьшение шрифта — пока не влезет по высоте (и не ниже 85% минимума).
        var size = measure(fontSize, width: space.width)
        while size.height > space.height, fontSize > minimumFont * 0.85 {
            fontSize *= 0.92
            size = measure(fontSize, width: space.width)
        }
        let frame = PlaqueLayout.place(size, near: CGPoint(x: source.midX, y: source.midY), in: space)

        // Ореол цвета фона: перевод, вышедший за затёртую область, читается и
        // поверх соседнего фона.
        context.saveGState()
        context.setShadow(offset: .zero, blur: max(2, fontSize * 0.18), color: backgroundColor.cgColor)
        for _ in 0..<2 {
            (text as NSString).draw(with: frame, options: [.usesLineFragmentOrigin], attributes: attributes(fontSize), context: nil)
        }
        context.restoreGState()
    }
}
#endif
