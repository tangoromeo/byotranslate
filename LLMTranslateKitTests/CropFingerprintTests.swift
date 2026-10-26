import CoreGraphics
import CoreText
import XCTest
@testable import LLMTranslateKit

/// Отпечаток надписи для кэша фрагментов: та же надпись (с другой рамкой, с шумом
/// фона) находится, другая — нет, даже если отличается одной цифрой.
final class CropFingerprintTests: XCTestCase {
    // MARK: - Синтетические «надписи» из прямоугольников

    private func image(glyphs: [CGRect], margin: Int = 10, extraLeft: Int = 0,
                       background: CGFloat = 1, ink: CGFloat = 0, noise: Int = 0) -> CGImage {
        let width = 220 + 2 * margin + extraLeft, height = 40 + 2 * margin
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: ink, alpha: 1)
        for glyph in glyphs { context.fill(glyph.offsetBy(dx: CGFloat(margin + extraLeft), dy: CGFloat(margin))) }
        if noise > 0, let data = context.data {
            // детерминированный шум ±noise, как подсветка от индикатора «Команд»
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
            var seed: UInt64 = 42
            for i in 0..<(width * height) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let delta = Int(seed >> 33) % (2 * noise + 1) - noise
                pixels[i] = UInt8(clamping: Int(pixels[i]) + delta)
            }
        }
        return context.makeImage()!
    }

    private let word = [CGRect(x: 0, y: 0, width: 20, height: 40), CGRect(x: 30, y: 10, width: 25, height: 30),
                        CGRect(x: 65, y: 0, width: 15, height: 40), CGRect(x: 90, y: 5, width: 40, height: 10),
                        CGRect(x: 140, y: 0, width: 80, height: 20)]

    private func signature(_ image: CGImage) -> CropFingerprint.Signature {
        CropFingerprint.signature(image)!
    }

    func test_sameText_sameKey() {
        XCTAssertEqual(signature(image(glyphs: word)).key, signature(image(glyphs: word)).key)
    }

    func test_differentFramingOfTheSameText_sameKey() {
        let tight = signature(image(glyphs: word, margin: 4))
        XCTAssertEqual(tight.key, signature(image(glyphs: word, margin: 14)).key)
        XCTAssertEqual(tight.key, signature(image(glyphs: word, margin: 6, extraLeft: 9)).key)
    }

    func test_backgroundNoise_isTheSameText() {
        let clean = signature(image(glyphs: word))
        let noisy = signature(image(glyphs: word, noise: 8))
        XCTAssertTrue(CropFingerprint.isSameText(clean, noisy))
    }

    func test_differentGlyph_isNotTheSameText() {
        var other = word
        other[2] = CGRect(x: 65, y: 20, width: 15, height: 20)
        XCTAssertFalse(CropFingerprint.isSameText(signature(image(glyphs: word)), signature(image(glyphs: other))))
    }

    func test_blankCrop_hasNoSignature() {
        XCTAssertNil(CropFingerprint.signature(image(glyphs: [])))
    }

    func test_lightTextOnDarkBackground_works() {
        let dark = signature(image(glyphs: word, background: 0.1, ink: 0.95))
        XCTAssertEqual(dark.key, signature(image(glyphs: word, margin: 16, background: 0.1, ink: 0.95)).key)
    }

    func test_distance_differentWidths_areNotCompared() {
        let a = CropFingerprint.Signature(width: 100, mask: Data(count: 300))
        let b = CropFingerprint.Signature(width: 110, mask: Data(count: 330))
        XCTAssertNil(CropFingerprint.distance(a, b))
        XCTAssertFalse(CropFingerprint.isSameText(a, b))
    }

    func test_tolerance_allowsAFewCells_butNotMore() {
        let width = 100, cells = width * CropFingerprint.height
        var bytes = [UInt8](repeating: 0, count: (cells + 7) / 8)
        let base = CropFingerprint.Signature(width: width, mask: Data(bytes))
        bytes[0] = 0b11 // 2 клетки
        XCTAssertTrue(CropFingerprint.isSameText(base, .init(width: width, mask: Data(bytes))))
        for i in 0..<4 { bytes[i] = 0xFF } // 32 клетки из 2400 (1,3%)
        XCTAssertFalse(CropFingerprint.isSameText(base, .init(width: width, mask: Data(bytes))))
    }

    // MARK: - Настоящий шрифт: строки, отличающиеся одной цифрой или буквой

    private func render(_ text: String, size: CGFloat = 42, noise: Int = 0) -> CGImage {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let width = Int(bounds.width) + 24, height = Int(size * 1.4)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textPosition = CGPoint(x: 12, y: size * 0.35)
        CTLineDraw(line, context)
        if noise > 0, let data = context.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
            var seed: UInt64 = 7
            for i in 0..<(width * height) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                pixels[i] = UInt8(clamping: Int(pixels[i]) + Int(seed >> 33) % (2 * noise + 1) - noise)
            }
        }
        return context.makeImage()!
    }

    func test_realText_oneDigitDifference_isNotTheSameText() {
        for (a, b) in [("Счёт …1234", "Счёт …1235"), ("Счёт …1234", "Счёт …1284"), ("8,90 ₪", "8,99 ₪"), ("123.45", "123.46")] {
            XCTAssertFalse(CropFingerprint.isSameText(signature(render(a)), signature(render(b))), "\(a) / \(b)")
        }
    }

    func test_realText_withBackgroundNoise_isTheSameText() {
        for text in ["Счёт …1234", "Добавить адрес", "Выбрать супермаркет"] {
            XCTAssertTrue(CropFingerprint.isSameText(signature(render(text)), signature(render(text, noise: 8))), text)
        }
    }
}
