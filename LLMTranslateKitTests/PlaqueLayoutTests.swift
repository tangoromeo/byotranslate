import CoreGraphics
import XCTest
@testable import LLMTranslateKit

/// Раскладка переводов «на месте»: подписи не налезают друг на друга.
final class PlaqueLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 2000)

    func test_twoButtonsInARow_growOnlyUpToEachOther() {
        // «Добавить адрес» и «Выбрать супермаркет» в одной строке
        let rects = [CGRect(x: 100, y: 1000, width: 300, height: 80), CGRect(x: 600, y: 1000, width: 300, height: 80)]
        let left = PlaqueLayout.freeSpace(for: 0, in: rects, bounds: bounds, gap: 10)
        let right = PlaqueLayout.freeSpace(for: 1, in: rects, bounds: bounds, gap: 10)
        // промежуток 400…600 делится пополам: 500 ± зазор/2
        XCTAssertEqual(left.maxX, 495)
        XCTAssertEqual(right.minX, 505)
        XCTAssertFalse(left.intersects(right))
    }

    func test_lineBelow_limitsVerticalGrowth() {
        let rects = [CGRect(x: 100, y: 100, width: 800, height: 60), CGRect(x: 100, y: 300, width: 800, height: 60)]
        let top = PlaqueLayout.freeSpace(for: 0, in: rects, bounds: bounds, gap: 10)
        XCTAssertEqual(top.maxY, 225) // середина промежутка 160…300 минус зазор/2
        XCTAssertEqual(top.minX, 0, "сосед ниже не ограничивает ширину")
        XCTAssertEqual(top.maxX, 1000)
    }

    func test_neighborsElsewhere_doNotLimit() {
        // сосед ниже, но в другой колонке, — не ограничивает ни ширину, ни высоту
        let rects = [CGRect(x: 100, y: 100, width: 200, height: 60), CGRect(x: 700, y: 500, width: 200, height: 60)]
        XCTAssertEqual(PlaqueLayout.freeSpace(for: 0, in: rects, bounds: bounds, gap: 10), bounds)
    }

    func test_overlappingNeighbor_isIgnored_andOwnRectAlwaysInside() {
        let rects = [CGRect(x: 100, y: 100, width: 300, height: 60), CGRect(x: 350, y: 120, width: 300, height: 60)]
        let space = PlaqueLayout.freeSpace(for: 0, in: rects, bounds: bounds, gap: 10)
        XCTAssertTrue(space.contains(rects[0]))
    }

    func test_freeSpaces_ofRowNeighbors_neverOverlap() {
        let rects = (0..<4).map { CGRect(x: 20 + Double($0) * 250, y: 500, width: 200, height: 50) }
        let spaces = rects.indices.map { PlaqueLayout.freeSpace(for: $0, in: rects, bounds: bounds, gap: 8) }
        for i in spaces.indices { for j in spaces.indices where i < j { XCTAssertFalse(spaces[i].intersects(spaces[j]), "\(i)/\(j)") } }
    }

    func test_place_centersAndClampsInsideSpace() {
        let space = CGRect(x: 0, y: 0, width: 500, height: 100)
        let centered = PlaqueLayout.place(CGSize(width: 100, height: 40), near: CGPoint(x: 250, y: 50), in: space)
        XCTAssertEqual(centered, CGRect(x: 200, y: 30, width: 100, height: 40))
        let clamped = PlaqueLayout.place(CGSize(width: 100, height: 40), near: CGPoint(x: 480, y: 95), in: space)
        XCTAssertEqual(clamped.maxX, 500)
        XCTAssertEqual(clamped.maxY, 100)
        let tooWide = PlaqueLayout.place(CGSize(width: 800, height: 40), near: CGPoint(x: 250, y: 50), in: space)
        XCTAssertEqual(tooWide.minX, 0)
    }
}
