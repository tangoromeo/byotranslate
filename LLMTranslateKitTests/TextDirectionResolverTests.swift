import XCTest
@testable import LLMTranslateKit

/// Раздел 9 ТЗ v1.2 (строка 410): «иврит и арабский — целевые языки, текст
/// должен выравниваться по правому краю при RTL-результате».
final class TextDirectionResolverTests: XCTestCase {
    func test_hebrew_isRightToLeft() {
        XCTAssertTrue(TextDirectionResolver.isRightToLeft(Locale.Language(identifier: "he")))
    }

    func test_arabic_isRightToLeft() {
        XCTAssertTrue(TextDirectionResolver.isRightToLeft(Locale.Language(identifier: "ar")))
    }

    func test_russian_isLeftToRight() {
        XCTAssertFalse(TextDirectionResolver.isRightToLeft(Locale.Language(identifier: "ru")))
    }

    func test_english_isLeftToRight() {
        XCTAssertFalse(TextDirectionResolver.isRightToLeft(Locale.Language(identifier: "en")))
    }

    func test_french_isLeftToRight() {
        XCTAssertFalse(TextDirectionResolver.isRightToLeft(Locale.Language(identifier: "fr")))
    }
}
