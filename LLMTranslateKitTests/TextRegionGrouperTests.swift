import XCTest
@testable import LLMTranslateKit

/// B6: склейка рамок детектора в блоки, которые пользователь воспринимает
/// как одно целое.
final class TextRegionGrouperTests: XCTestCase {
    private let image = CGSize(width: 1000, height: 2000)

    private func group(_ rects: [CGRect]) -> [TextRegion] {
        TextRegionGrouper.group(pixelRects: rects, imageSize: image)
    }

    func test_empty_returnsNoRegions() {
        XCTAssertTrue(group([]).isEmpty)
    }

    func test_zeroSizedImage_returnsNoRegions() {
        XCTAssertTrue(TextRegionGrouper.group(pixelRects: [CGRect(x: 0, y: 0, width: 50, height: 20)], imageSize: .zero).isEmpty)
    }

    func test_tinyRects_areDroppedAsNoise() {
        XCTAssertTrue(group([CGRect(x: 10, y: 10, width: 3, height: 3)]).isEmpty)
    }

    func test_wordsOnOneLine_mergeIntoOneRegion() {
        let regions = group([
            CGRect(x: 100, y: 500, width: 80, height: 30),
            CGRect(x: 190, y: 502, width: 120, height: 28), // зазор 10 < высоты
        ])
        XCTAssertEqual(regions.count, 1)
    }

    func test_wordsFarApartOnOneRow_stayApart() {
        let regions = group([
            CGRect(x: 50, y: 500, width: 80, height: 30),
            CGRect(x: 700, y: 500, width: 80, height: 30), // зазор 570 >> высоты
        ])
        XCTAssertEqual(regions.count, 2)
    }

    func test_consecutiveLinesOfParagraph_mergeIntoOneBlock() {
        let regions = group([
            CGRect(x: 100, y: 500, width: 600, height: 30),
            CGRect(x: 100, y: 540, width: 600, height: 30), // зазор 10 < 0.7 * 30
            CGRect(x: 100, y: 580, width: 400, height: 30), // короткая последняя строка
        ])
        XCTAssertEqual(regions.count, 1)
    }

    func test_farApartLines_areSeparateRegions() {
        let regions = group([
            CGRect(x: 100, y: 500, width: 600, height: 30),
            CGRect(x: 100, y: 700, width: 600, height: 30),
        ])
        XCTAssertEqual(regions.count, 2)
    }

    func test_titleAndBodyWithDifferentHeights_doNotMerge() {
        let regions = group([
            CGRect(x: 100, y: 400, width: 500, height: 60), // заголовок
            CGRect(x: 100, y: 470, width: 600, height: 24), // текст: разница высот > 1.5
        ])
        XCTAssertEqual(regions.count, 2)
    }

    func test_sideBySideColumns_doNotMerge() {
        let regions = group([
            CGRect(x: 50, y: 500, width: 200, height: 30),
            CGRect(x: 600, y: 540, width: 200, height: 30), // нет общей зоны по x
        ])
        XCTAssertEqual(regions.count, 2)
    }

    func test_rightAlignedParagraph_mergesLikeHebrew() {
        let regions = group([
            CGRect(x: 300, y: 500, width: 600, height: 30),
            CGRect(x: 500, y: 540, width: 400, height: 30), // общий правый край
        ])
        XCTAssertEqual(regions.count, 1)
    }

    /// Регрессия с телефона: строки абзаца из слов разной высоты (иврит +
    /// латиница) не склеивались, потому что «высота строки» считалась как
    /// среднее по словам, а не как высота самой строки.
    func test_paragraphLinesBuiltFromWordsOfMixedHeights_stillMerge() {
        func line(y: CGFloat, wordHeights: [CGFloat]) -> [CGRect] {
            var x: CGFloat = 100
            return wordHeights.map { h in
                defer { x += 130 }
                return CGRect(x: x, y: y + (70 - h), width: 120, height: h) // общая нижняя линия
            }
        }
        let rects = line(y: 500, wordHeights: [70, 36, 36, 36])
            + line(y: 566, wordHeights: [70, 70, 70])   // шаг 66 при высоте 70: рамки налезают на 4 px
            + line(y: 632, wordHeights: [70, 36, 36, 36])
        XCTAssertEqual(group(rects).count, 1)
    }

    func test_regions_areReadingOrderedTopToBottom_andNormalized() {
        let regions = group([
            CGRect(x: 100, y: 1500, width: 500, height: 40),
            CGRect(x: 100, y: 200, width: 500, height: 40),
        ])
        XCTAssertEqual(regions.map(\.id), [0, 1])
        XCTAssertEqual(regions[0].rect.minY, 200.0 / 2000.0, accuracy: 0.0001)
        XCTAssertEqual(regions[1].rect.minY, 1500.0 / 2000.0, accuracy: 0.0001)
        XCTAssertEqual(regions[0].rect.width, 0.5, accuracy: 0.0001)
    }

    func test_cropRect_addsPaddingAndStaysInsideImage() {
        let region = TextRegion(id: 0, rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02))
        let crop = TextRegionGrouper.cropRect(for: region, imageSize: image)
        // область 500x40 px, поле = max(10, 20) = 20
        XCTAssertEqual(crop.width, 540, accuracy: 2)
        XCTAssertEqual(crop.height, 80, accuracy: 2)
        XCTAssertTrue(CGRect(origin: .zero, size: image).contains(crop))
    }

    func test_cropRect_nearEdge_isClampedToImage() {
        let region = TextRegion(id: 0, rect: CGRect(x: 0, y: 0, width: 0.3, height: 0.01))
        let crop = TextRegionGrouper.cropRect(for: region, imageSize: image)
        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0)
        XCTAssertTrue(CGRect(origin: .zero, size: image).contains(crop))
    }
}

extension TextRegionGrouperTests {
    func test_region_carriesLineHeightOfParagraph_notBlockHeight() {
        let regions = TextRegionGrouper.group(
            pixelRects: [
                CGRect(x: 100, y: 500, width: 600, height: 30),
                CGRect(x: 100, y: 540, width: 600, height: 30),
                CGRect(x: 100, y: 580, width: 400, height: 30),
            ],
            imageSize: CGSize(width: 1000, height: 2000)
        )
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].lineHeight, 30.0 / 2000.0, accuracy: 0.0001)
        XCTAssertGreaterThan(regions[0].rect.height, regions[0].lineHeight * 2)
    }
}

extension TextRegionGrouperTests {
    /// Одна строка, найденная детектором на нескольких масштабах с чуть
    /// разными границами, должна остаться одной областью.
    func test_sameLineDetectedAtSeveralScales_staysOneRegion() {
        let regions = TextRegionGrouper.group(
            pixelRects: [
                CGRect(x: 811, y: 1085, width: 286, height: 25),
                CGRect(x: 813, y: 1083, width: 284, height: 28),
                CGRect(x: 810, y: 1080, width: 290, height: 34),
            ],
            imageSize: CGSize(width: 1188, height: 2576)
        )
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].lineHeight * 2576, 25, accuracy: 1) // первая (масштаб 1.0) побеждает
    }

    func test_deduplicate_keepsDistinctRects_andFirstOfDuplicates() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 20)
        let b = CGRect(x: 2, y: 1, width: 98, height: 22)
        let c = CGRect(x: 0, y: 200, width: 100, height: 20)
        XCTAssertEqual(TextRegionGrouper.deduplicate([a, b, c]), [a, c])
    }
}

final class TextRegionDetectorBudgetTests: XCTestCase {
    func test_scaleOne_isAlwaysAllowed_evenOverBudget() {
        XCTAssertTrue(TextRegionDetector.usableScales(for: CGSize(width: 9000, height: 9000), budget: 1).contains(1))
    }

    func test_photoInExtension_skipsHeavyScales() {
        // 2048×1536 ≈ 3,1 Мп; бюджет расширения 9 Мп → 1.5× (7,1 Мп) можно, 1.75× (9,6 Мп) нельзя
        let scales = TextRegionDetector.usableScales(for: CGSize(width: 2048, height: 1536), budget: 9_000_000)
        XCTAssertTrue(scales.contains(1.5))
        XCTAssertFalse(scales.contains(1.75))
        XCTAssertFalse(scales.contains(2))
    }

    func test_photoInApp_allowsDoubleButNothingAboveBudget() {
        let size = CGSize(width: 3000, height: 2250)
        let scales = TextRegionDetector.usableScales(for: size, budget: 30_000_000)
        XCTAssertTrue(scales.contains(2))
        for scale in scales { XCTAssertLessThanOrEqual(size.width * scale * size.height * scale, 30_000_000) }
    }

    func test_downscalePassesAreAlwaysCheap() {
        XCTAssertTrue(TextRegionDetector.usableScales(for: CGSize(width: 3000, height: 2250), budget: 7_000_000).contains(0.5))
    }
}
