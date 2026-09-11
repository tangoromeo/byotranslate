import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 5 ТЗ v1.2: граничные значения порогов словарного режима —
/// 4 слова, 5 слов, 30 символов, 31 символ.
final class DictionaryModeDetectorTests: XCTestCase {
    func test_fourWords_thirtyCharacters_usesDictionaryMode() {
        let text = "aaaaaa bbbbbbb ccccccc ddddddd" // 4 слова, 30 символов
        XCTAssertEqual(text.count, 30)
        XCTAssertTrue(DictionaryModeDetector.shouldUseDictionaryMode(for: text))
    }

    func test_fiveWords_underCharacterLimit_doesNotUseDictionaryMode() {
        let text = "a b c d e" // 5 слов, 9 символов
        XCTAssertFalse(DictionaryModeDetector.shouldUseDictionaryMode(for: text))
    }

    func test_thirtyOneCharacters_singleWord_doesNotUseDictionaryMode() {
        let text = String(repeating: "a", count: 31) // 1 слово, 31 символ
        XCTAssertFalse(DictionaryModeDetector.shouldUseDictionaryMode(for: text))
    }

    func test_thirtyCharacters_singleWord_usesDictionaryMode() {
        let text = String(repeating: "a", count: 30)
        XCTAssertTrue(DictionaryModeDetector.shouldUseDictionaryMode(for: text))
    }

    func test_singleWordSelection_usesDictionaryMode() {
        XCTAssertTrue(DictionaryModeDetector.shouldUseDictionaryMode(for: "hello"))
    }

    func test_longParagraph_doesNotUseDictionaryMode() {
        let text = "This is a much longer paragraph that clearly exceeds both the word and character thresholds for dictionary mode."
        XCTAssertFalse(DictionaryModeDetector.shouldUseDictionaryMode(for: text))
    }
}
