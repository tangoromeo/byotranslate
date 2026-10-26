import CoreGraphics
import XCTest
@testable import LLMTranslateKit

final class ScreenLayoutDescriberTests: XCTestCase {
    private func item(_ number: Int, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 0.02,
                      line: CGFloat = 0.02, button: Bool = false) -> ScreenLayoutDescriber.Item {
        .init(number: number, rect: CGRect(x: x, y: y, width: w, height: h), lineHeight: line, onColoredBackground: button)
    }

    func test_headerListAndButton() {
        let items = [
            item(1, x: 0.3, y: 0.08, w: 0.4, h: 0.035, line: 0.035),        // заголовок
            item(2, x: 0.08, y: 0.20, w: 0.5), item(3, x: 0.08, y: 0.25, w: 0.4),
            item(4, x: 0.08, y: 0.30, w: 0.45), item(5, x: 0.08, y: 0.35, w: 0.3), // список
            item(6, x: 0.2, y: 0.9, w: 0.6, button: true),                     // кнопка
        ]
        let text = ScreenLayoutDescriber.describe(items)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3, text)
        XCTAssertTrue(lines[0].hasPrefix("1: вверху, по центру, крупный шрифт"), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("2–5: список однотипных пунктов, слева"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("6: внизу"), lines[2])
        XCTAssertTrue(lines[2].contains("кнопку"), lines[2])
    }

    func test_twoAlignedItems_areNotCalledAList() {
        let text = ScreenLayoutDescriber.describe([item(1, x: 0.1, y: 0.3, w: 0.3), item(2, x: 0.1, y: 0.35, w: 0.3)])
        XCTAssertFalse(text.contains("список"), text)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
    }

    func test_differentFontSizes_breakTheList() {
        let items = [item(1, x: 0.1, y: 0.2, w: 0.3), item(2, x: 0.1, y: 0.25, w: 0.3),
                     item(3, x: 0.1, y: 0.30, w: 0.3, h: 0.04, line: 0.04), item(4, x: 0.1, y: 0.36, w: 0.3)]
        XCTAssertFalse(ScreenLayoutDescriber.describe(items).contains("список"))
    }

    func test_ordersTopToBottom_regardlessOfInputOrder() {
        let text = ScreenLayoutDescriber.describe([item(2, x: 0.1, y: 0.7, w: 0.3), item(1, x: 0.1, y: 0.1, w: 0.3)])
        XCTAssertTrue(text.hasPrefix("1:"), text)
    }

    func test_multilineParagraph() {
        let text = ScreenLayoutDescriber.describe([item(1, x: 0.05, y: 0.4, w: 0.9, h: 0.1, line: 0.02)])
        XCTAssertTrue(text.contains("во всю ширину"))
        XCTAssertTrue(text.contains("несколько строк"))
    }

    func test_empty() {
        XCTAssertEqual(ScreenLayoutDescriber.describe([]), "")
    }
}

final class RegionsPromptTests: XCTestCase {
    func test_regionsPrompt_asksForConsistency_notIndependence() {
        let prompt = PromptBuilder.defaultRegionsSystemPrompt
        XCTAssertFalse(prompt.contains("независимо"))
        XCTAssertTrue(prompt.contains("ОДНОГО экрана"))
        XCTAssertTrue(prompt.contains("одинаково"))
        XCTAssertTrue(prompt.contains("[{\"n\":1,\"t\":\"перевод\"}"))
    }
}
