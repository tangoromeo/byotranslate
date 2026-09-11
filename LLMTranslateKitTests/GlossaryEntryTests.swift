import XCTest
@testable import LLMTranslateKit

/// Раздел 8.1/13.3 ТЗ v1.2: сворачивание списка глоссария в словарь для
/// `PromptBuilder`.
final class GlossaryEntryTests: XCTestCase {
    func test_emptyList_producesEmptyDictionary() {
        XCTAssertTrue(GlossaryEntry.asDictionary([]).isEmpty)
    }

    func test_blankTerm_isFiltered() {
        let entries = [
            GlossaryEntry(term: "", translation: "пусто"),
            GlossaryEntry(term: "   ", translation: "тоже пусто"),
            GlossaryEntry(term: "API", translation: "программный интерфейс"),
        ]
        XCTAssertEqual(GlossaryEntry.asDictionary(entries), ["API": "программный интерфейс"])
    }

    func test_duplicateTerm_lastEntryWins() {
        let entries = [
            GlossaryEntry(term: "API", translation: "первый вариант"),
            GlossaryEntry(term: "API", translation: "второй вариант"),
        ]
        XCTAssertEqual(GlossaryEntry.asDictionary(entries), ["API": "второй вариант"])
    }

    func test_orderOfEntries_doesNotAffectResult() {
        let a = [
            GlossaryEntry(term: "API", translation: "интерфейс"),
            GlossaryEntry(term: "SDK", translation: "набор инструментов"),
        ]
        let b = Array(a.reversed())
        XCTAssertEqual(GlossaryEntry.asDictionary(a), GlossaryEntry.asDictionary(b))
    }

    func test_termWithSurroundingWhitespace_isTrimmedForFiltering() {
        let entries = [GlossaryEntry(term: "  API  ", translation: "интерфейс")]
        XCTAssertFalse(GlossaryEntry.asDictionary(entries).isEmpty)
    }
}
