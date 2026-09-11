import XCTest
@testable import LLMTranslateKit

/// Раздел 14, п. 6 ТЗ: даунскейл, ступенчатое понижение качества,
/// корректный отказ на неподъёмном изображении. Реальное кодирование
/// JPEG/PNG требует UIKit и не тестируется через кросс-платформенный
/// SPM-харнесс этой сессии (см. `ImagePreparation` doc-comment) — здесь
/// проверяется вся чистая логика, из которой оно строится.
final class ImageResizeMathTests: XCTestCase {
    func test_downscalesLongSideOnly_preservingAspectRatio() {
        let result = ImageResizeMath.targetSize(originalWidth: 1290, originalHeight: 2796, maxLongSide: 1568)
        XCTAssertEqual(result.height, 1568)
        XCTAssertEqual(result.width, 723) // 1290 * (1568/2796), округлено
    }

    func test_landscapeImage_downscalesWidthAsLongSide() {
        let result = ImageResizeMath.targetSize(originalWidth: 3000, originalHeight: 1000, maxLongSide: 1568)
        XCTAssertEqual(result.width, 1568)
        XCTAssertEqual(result.height, 523)
    }

    func test_doesNotEnlargeSmallerImages() {
        let result = ImageResizeMath.targetSize(originalWidth: 400, originalHeight: 300, maxLongSide: 1568)
        XCTAssertEqual(result.width, 400)
        XCTAssertEqual(result.height, 300)
    }

    func test_exactlyAtLimit_staysUnchanged() {
        let result = ImageResizeMath.targetSize(originalWidth: 1568, originalHeight: 800, maxLongSide: 1568)
        XCTAssertEqual(result.width, 1568)
        XCTAssertEqual(result.height, 800)
    }

    func test_squareImage() {
        let result = ImageResizeMath.targetSize(originalWidth: 3000, originalHeight: 3000, maxLongSide: 1024)
        XCTAssertEqual(result.width, 1024)
        XCTAssertEqual(result.height, 1024)
    }
}

final class ImageQualityLadderTests: XCTestCase {
    func test_stepsMatchTZOrder() {
        // Раздел 10.7 ТЗ: 1568px/0.8 → 1568px/0.5 → 1024px/0.5 → ошибка.
        XCTAssertEqual(ImageQualityLadder.steps.count, 3)
        XCTAssertEqual(ImageQualityLadder.steps[0], .init(maxLongSide: 1568, jpegQuality: 0.8))
        XCTAssertEqual(ImageQualityLadder.steps[1], .init(maxLongSide: 1568, jpegQuality: 0.5))
        XCTAssertEqual(ImageQualityLadder.steps[2], .init(maxLongSide: 1024, jpegQuality: 0.5))
    }

    func test_firstFittingStep_picksFirstUnderLimit() {
        let index = ImageQualityLadder.firstFittingStepIndex(
            byteCounts: [5_000_000, 3_000_000, 2_000_000],
            limitBytes: 4_000_000
        )
        XCTAssertEqual(index, 1)
    }

    func test_firstFittingStep_firstStepAlreadyFits() {
        let index = ImageQualityLadder.firstFittingStepIndex(byteCounts: [1_000_000], limitBytes: 4_000_000)
        XCTAssertEqual(index, 0)
    }

    /// Раздел 10.7 ТЗ: «затем ошибка» — ничего не влезло даже на последнем шаге.
    func test_firstFittingStep_nothingFits_returnsNil() {
        let index = ImageQualityLadder.firstFittingStepIndex(
            byteCounts: [9_000_000, 8_000_000, 7_000_000],
            limitBytes: 4_000_000
        )
        XCTAssertNil(index)
    }
}

final class Base64PayloadSizeTests: XCTestCase {
    func test_base64EncodedByteCount_matchesRealEncoding() {
        for rawSize in [0, 1, 2, 3, 4, 100, 3_000_000] {
            let raw = Data(repeating: 0, count: rawSize)
            XCTAssertEqual(
                ImagePreparation.base64EncodedByteCount(for: raw.count),
                raw.base64EncodedString().utf8.count,
                "raw size \(rawSize)"
            )
        }
    }
}

final class PNGSignatureTests: XCTestCase {
    func test_recognizesPNGSignature() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        XCTAssertTrue(png.isPNGSignature)
    }

    func test_rejectsNonPNGData() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        XCTAssertFalse(jpeg.isPNGSignature)
    }

    func test_rejectsTooShortData() {
        XCTAssertFalse(Data([0x89, 0x50]).isPNGSignature)
    }
}
