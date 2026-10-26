#if canImport(UIKit)
import SwiftUI
import UIKit
import os.log

private let log = Logger(subsystem: "com.tyrex.llmtranslate", category: "region-overlay")

/// Цвет фона под областью текста, замеренный по краям рамки: плашка
/// закрашивает оригинал «в тон», а не белым пятном на тёмной теме.
struct RegionBackground: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
    /// Читаемый цвет текста на этом фоне.
    var textColor: Color {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.55 ? .black : .white
    }
}

/// Раздел B6, этап 3: перевод всех областей скриншота для режима «Плашки».
/// Фрагменты склеиваются в листы (`RegionSheetPlanner`), на каждый лист —
/// один запрос; листы идут параллельно, и плашки появляются по мере готовности.
/// Всё в памяти (раздел 10.7 ТЗ): ни кропы, ни листы на диск не пишутся.
@MainActor
final class RegionOverlayModel: ObservableObject {
    /// `TextRegion.id` → перевод.
    @Published private(set) var translations: [Int: String] = [:]
    @Published private(set) var backgrounds: [Int: RegionBackground] = [:]
    /// Области, чьи листы ещё в пути.
    @Published private(set) var pendingIDs: Set<Int> = []
    @Published private(set) var error: TranslationError?
    @Published private(set) var isRunning = false
    @Published private(set) var isTargetRTL = false

    private var startedFor: Data?
    private var roundImageData = Data()
    private var generation = 0

    /// Сбрасывает всё, что относится к прошлому скриншоту; запросы, ещё
    /// летящие по нему, после этого результат не запишут.
    func reset() {
        generation += 1
        startedFor = nil
        translations = [:]
        backgrounds = [:]
        pendingIDs = []
        error = nil
        isRunning = false
    }

    /// Идемпотентно для того же скриншота: переключение режимов туда-обратно
    /// не должно платить за перевод второй раз.
    func start(imageData: Data, regions: [TextRegion], appGroupSuiteName: String) async {
        guard startedFor != imageData, !regions.isEmpty else { return }
        reset()
        startedFor = imageData
        roundImageData = imageData
        let myGeneration = generation
        isRunning = true
        isTargetRTL = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName)
            .map { TextDirectionResolver.isRightToLeft($0.primaryTargetLanguage) } ?? false

        // Кэш фрагментов: одинаковые надписи (тот же пункт меню на повторном
        // снимке) берутся из кэша — без запроса и всегда одинаково.
        let cache = RegionTranslationCache(appGroupSuiteName: appGroupSuiteName)
        var fingerprints: [Int: CropFingerprint.Signature] = [:]
        var fromCache: Set<Int> = []
        if let cache {
            let prepared = await Task.detached(priority: .userInitiated) {
                RegionOverlayPreparation.fingerprints(imageData: imageData, regions: regions)
            }.value
            guard myGeneration == generation else { return }
            fingerprints = prepared.byRegion
            backgrounds.merge(prepared.backgrounds) { current, _ in current }
            var unique: [String: CropFingerprint.Signature] = [:]
            for signature in fingerprints.values { unique[signature.key] = signature }
            let hits = cache.lookup(Array(unique.values))
            for (id, signature) in fingerprints {
                guard let text = hits[signature.key] else { continue }
                // Пустая строка в кэше — «модель здесь перевода не даёт» (значок,
                // цифры): плашки нет, но и запроса тоже.
                if !text.isEmpty { translations[id] = text }
                fromCache.insert(id)
            }
            log.notice("region cache: \(fromCache.count, privacy: .public) of \(regions.count, privacy: .public) from cache")
        }

        // Фон под всеми надписями экрана — для раскладки («на цветной плашке»).
        if regions.contains(where: { backgrounds[$0.id] == nil }) {
            let sampled = await Task.detached(priority: .userInitiated) {
                RegionOverlayPreparation.backgrounds(imageData: imageData, regions: regions)
            }.value
            guard myGeneration == generation else { return }
            backgrounds.merge(sampled) { current, _ in current }
        }

        // Модели иногда пропускают номер или отдают пустой перевод: областям,
        // оставшимся без перевода, даём один повторный проход — с тем же контекстом
        // экрана и уже переведёнными надписями.
        var remaining = regions.filter { translations[$0.id] == nil && !fromCache.contains($0.id) }
        for round in 0..<2 {
            guard !remaining.isEmpty, myGeneration == generation else { break }
            let covered = await runRound(
                regions: remaining, screen: regions, appGroupSuiteName: appGroupSuiteName, myGeneration: myGeneration
            )
            guard myGeneration == generation, error == nil else { break }
            remaining = regions.filter { covered.contains($0.id) && translations[$0.id] == nil }
            log.notice("regions round \(round, privacy: .public): untranslated=\(remaining.count, privacy: .public) of \(regions.count, privacy: .public)")
        }
        guard myGeneration == generation else { return }
        if let cache {
            var fresh: [(signature: CropFingerprint.Signature, translation: String)] = []
            // Без ошибки сети/ключа: области, которым модель так и не дала перевод
            // после повторного прохода, запоминаем пустой строкой.
            let sentToModel = error == nil
            for (id, fingerprint) in fingerprints where !fromCache.contains(id) {
                if let text = translations[id] {
                    fresh.append((fingerprint, text))
                } else if sentToModel {
                    fresh.append((fingerprint, ""))
                }
            }
            cache.store(fresh)
        }
        isRunning = false
    }

    /// Один проход: все листы одним запросом вместе с раскладкой экрана и уже
    /// известными переводами — модель видит надписи экрана вместе, а не по листу.
    /// Возвращает id областей, которые попали в листы.
    private func runRound(
        regions: [TextRegion],
        screen: [TextRegion],
        appGroupSuiteName: String,
        myGeneration: Int
    ) async -> Set<Int> {
        let imageData = roundImageData
        let prepared = await Task.detached(priority: .userInitiated) {
            RegionOverlayPreparation.prepare(imageData: imageData, regions: regions)
        }.value
        guard myGeneration == generation else { return [] }
        backgrounds.merge(prepared.backgrounds) { current, _ in current }
        let covered = Set(prepared.sheets.flatMap(\.regionIDs))
        guard !covered.isEmpty else { return covered }
        pendingIDs.formUnion(covered)

        let session = TranslationSession(appGroupSuiteName: appGroupSuiteName)
        await session.startRegionBatch(
            sheets: prepared.sheets.map(\.data),
            context: screenContext(screen: screen, toTranslate: covered)
        )
        guard myGeneration == generation else { return covered }
        if let failure = session.currentError {
            error = error ?? failure
        } else {
            // Метка на листе — id + 1 (см. RegionSheetRenderer).
            let parsed = RegionTranslationParser.parse(session.translation)
            for id in covered {
                if let text = parsed[id + 1] { translations[id] = text }
            }
        }
        pendingIDs.subtract(covered)
        return covered
    }

    /// Текст запроса: раскладка всего экрана, уже известные переводы (для
    /// согласованности) и какие номера переводить сейчас.
    func screenContext(screen: [TextRegion], toTranslate: Set<Int>) -> String {
        let pageBackground = Self.pageBackground(of: screen.compactMap { backgrounds[$0.id] })
        let items = screen.map { region in
            ScreenLayoutDescriber.Item(
                number: region.id + 1,
                rect: region.rect,
                lineHeight: region.lineHeight,
                onColoredBackground: backgrounds[region.id].map { Self.distance($0, pageBackground) > 0.25 } ?? false
            )
        }
        var text = "Надписи экрана сверху вниз (номер: где и что):\n" + ScreenLayoutDescriber.describe(items)
        let known = screen
            .filter { !toTranslate.contains($0.id) }
            .compactMap { region in translations[region.id].map { "\(region.id + 1): «\($0)»" } }
        if !known.isEmpty {
            text += "\n\nУже переведены (не повторяй, держи те же термины):\n" + known.joined(separator: "\n")
        }
        let numbers = toTranslate.sorted().map { String($0 + 1) }.joined(separator: ", ")
        text += "\n\nПереведи фрагменты на изображениях: " + numbers
        return text
    }

    /// Подсказка для перевода одного фрагмента по тапу: раскладка экрана и уже
    /// известные переводы соседних надписей (если «Весь экран» уже отработал).
    func fragmentContext(regionID: Int, screen: [TextRegion]) -> String {
        var text = "Изображение — фрагмент №\(regionID + 1) экрана приложения. Переведи только текст на изображении, "
            + "используя остальное как контекст.\n\n"
        text += screenContext(screen: screen, toTranslate: [regionID])
            .replacingOccurrences(of: "\n\nПереведи фрагменты на изображениях: \(regionID + 1)", with: "")
        return text
    }

    private static func pageBackground(of colors: [RegionBackground]) -> RegionBackground {
        guard !colors.isEmpty else { return RegionBackground(red: 1, green: 1, blue: 1) }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return RegionBackground(red: median(colors.map(\.red)), green: median(colors.map(\.green)), blue: median(colors.map(\.blue)))
    }

    private static func distance(_ a: RegionBackground, _ b: RegionBackground) -> Double {
        ((a.red - b.red) * (a.red - b.red) + (a.green - b.green) * (a.green - b.green) + (a.blue - b.blue) * (a.blue - b.blue)).squareRoot()
    }

    /// «Повторить» после ошибки: те же области, новые запросы.
    func retry(imageData: Data, regions: [TextRegion], appGroupSuiteName: String) async {
        startedFor = nil
        await start(imageData: imageData, regions: regions, appGroupSuiteName: appGroupSuiteName)
    }
}

struct PreparedRegionSheet: Sendable {
    let regionIDs: [Int]
    let data: Data
}

/// Вне `@MainActor`: декодирование, кропы и рендеринг листов — тяжёлая работа.
enum RegionOverlayPreparation {
    struct Fingerprints: Sendable {
        let byRegion: [Int: CropFingerprint.Signature]
        let backgrounds: [Int: RegionBackground]
    }


    static func backgrounds(imageData: Data, regions: [TextRegion]) -> [Int: RegionBackground] {
        guard let image = ScreenshotImageTools.normalizedCGImage(from: imageData) else { return [:] }
        return RegionBackgroundSampler.sample(image: image, regions: regions)
    }

    /// Отпечатки надписей по точной рамке области (без полей: поля тянут соседей,
    /// и одна и та же кнопка в другом окружении получила бы другой отпечаток).
    static func fingerprints(imageData: Data, regions: [TextRegion]) -> Fingerprints {
        guard let image = ScreenshotImageTools.normalizedCGImage(from: imageData) else {
            return Fingerprints(byRegion: [:], backgrounds: [:])
        }
        let width = Double(image.width), height = Double(image.height)
        var result: [Int: CropFingerprint.Signature] = [:]
        for region in regions {
            let rect = CGRect(
                x: region.rect.minX * width, y: region.rect.minY * height,
                width: region.rect.width * width, height: region.rect.height * height
            ).integral
            if let crop = image.cropping(to: rect), let fingerprint = CropFingerprint.signature(crop) {
                result[region.id] = fingerprint
            }
        }
        return Fingerprints(byRegion: result, backgrounds: RegionBackgroundSampler.sample(image: image, regions: regions))
    }

    struct Result: Sendable {
        let sheets: [PreparedRegionSheet]
        let backgrounds: [Int: RegionBackground]
    }

    static func prepare(imageData: Data, regions: [TextRegion]) -> Result {
        guard let image = ScreenshotImageTools.normalizedCGImage(from: imageData) else {
            return Result(sheets: [], backgrounds: [:])
        }
        let imageSize = CGSize(width: image.width, height: image.height)
        var crops: [Int: CGImage] = [:]
        var sizes: [CGSize] = []
        for region in regions {
            let rect = TextRegionGrouper.cropRect(for: region, imageSize: imageSize)
            if let crop = image.cropping(to: rect) {
                crops[region.id] = crop
                sizes.append(CGSize(width: crop.width, height: crop.height))
            } else {
                sizes.append(.zero)
            }
        }
        // `RegionSheetPlanner` индексирует по позиции в `regions`.
        let sheets = RegionSheetPlanner.plan(cropSizes: sizes).compactMap { sheet -> PreparedRegionSheet? in
            let ids = sheet.rows.map { regions[$0.index].id }
            guard let data = RegionSheetRenderer.render(sheet, crops: crops, regions: regions) else { return nil }
            return PreparedRegionSheet(regionIDs: ids, data: data)
        }
        return Result(sheets: sheets, backgrounds: RegionBackgroundSampler.sample(image: image, regions: regions))
    }
}

enum RegionSheetRenderer {
    static func render(_ sheet: RegionSheetPlanner.Sheet, crops: [Int: CGImage], regions: [TextRegion]) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: sheet.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: sheet.size))
            for row in sheet.rows {
                let region = regions[row.index]
                guard let crop = crops[region.id] else { continue }
                UIImage(cgImage: crop).draw(in: row.frame)
                UIColor(white: 0.7, alpha: 1).setStroke()
                context.stroke(row.frame.insetBy(dx: -1, dy: -1))

                let fontSize = min(40, max(20, row.frame.height * 1.1))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.black,
                ]
                let label = "\(region.id + 1)" as NSString
                let labelSize = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(
                        x: RegionSheetPlanner.padding + RegionSheetPlanner.labelWidth - 10 - labelSize.width,
                        y: row.frame.midY - labelSize.height / 2
                    ),
                    withAttributes: attributes
                )
            }
        }
        return image.pngData()
    }
}

enum RegionBackgroundSampler {
    /// Медиана по восьми точкам вокруг рамки (снаружи, по краям и углам):
    /// внутри рамки лежит сам текст и среднее по ней было бы грязным.
    static func sample(image: CGImage, regions: [TextRegion]) -> [Int: RegionBackground] {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return [:] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [:] }

        func pixel(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
            let offset = (cy * width + cx) * 4
            return (Double(pixels[offset]) / 255, Double(pixels[offset + 1]) / 255, Double(pixels[offset + 2]) / 255)
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

        var result: [Int: RegionBackground] = [:]
        for region in regions {
            let rect = CGRect(
                x: region.rect.minX * Double(width), y: region.rect.minY * Double(height),
                width: region.rect.width * Double(width), height: region.rect.height * Double(height)
            )
            let margin = max(3, region.lineHeight * Double(height) * 0.25)
            let xs = [rect.minX - margin, rect.midX, rect.maxX + margin]
            let ys = [rect.minY - margin, rect.midY, rect.maxY + margin]
            var samples: [(Double, Double, Double)] = []
            for (xi, x) in xs.enumerated() {
                for (yi, y) in ys.enumerated() where !(xi == 1 && yi == 1) {
                    samples.append(pixel(Int(x), Int(y)))
                }
            }
            result[region.id] = RegionBackground(
                red: median(samples.map(\.0)), green: median(samples.map(\.1)), blue: median(samples.map(\.2))
            )
        }
        return result
    }
}
#endif
