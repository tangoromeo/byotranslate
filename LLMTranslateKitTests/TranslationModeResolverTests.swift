import XCTest
@testable import LLMTranslateKit

/// Раздел 11.3 ТЗ v1.2: приоритет словарного режима над `notesMode`, и
/// поведение `notesMode` на длинном/коротком тексте.
final class TranslationModeResolverTests: XCTestCase {
    private let shortText = "hello" // короче порога словарного режима
    private let longText = "This is a much longer paragraph that clearly exceeds both thresholds."

    func test_shortText_dictionaryEnabled_alwaysDictionary_regardlessOfNotesMode() {
        for notesMode: NotesMode in [.off, .shortOnly, .always] {
            let mode = TranslationModeResolver.resolve(text: shortText, dictionaryModeEnabled: true, notesMode: notesMode)
            XCTAssertEqual(mode, .dictionary, "notesMode=\(notesMode)")
        }
    }

    func test_shortText_dictionaryDisabled_notesOff_isPlain() {
        let mode = TranslationModeResolver.resolve(text: shortText, dictionaryModeEnabled: false, notesMode: .off)
        XCTAssertEqual(mode, .plain)
    }

    func test_shortText_dictionaryDisabled_notesShortOnly_isWithNotes() {
        let mode = TranslationModeResolver.resolve(text: shortText, dictionaryModeEnabled: false, notesMode: .shortOnly)
        XCTAssertEqual(mode, .withNotes)
    }

    func test_longText_notesShortOnly_isPlain() {
        let mode = TranslationModeResolver.resolve(text: longText, dictionaryModeEnabled: true, notesMode: .shortOnly)
        XCTAssertEqual(mode, .plain)
    }

    func test_longText_notesAlways_isWithNotes() {
        let mode = TranslationModeResolver.resolve(text: longText, dictionaryModeEnabled: true, notesMode: .always)
        XCTAssertEqual(mode, .withNotes)
    }

    func test_longText_notesOff_isPlain() {
        let mode = TranslationModeResolver.resolve(text: longText, dictionaryModeEnabled: true, notesMode: .off)
        XCTAssertEqual(mode, .plain)
    }
}
