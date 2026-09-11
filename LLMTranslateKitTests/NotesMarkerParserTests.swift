import XCTest
@testable import LLMTranslateKit

/// Раздел 15, п. 2 ТЗ v1.2: маркер целиком в одном чанке; маркер, разорванный
/// между чанками в каждой возможной позиции; маркера нет вовсе; маркер есть,
/// блок пуст; текст, начинающийся с символа `⟦`, который не является маркером.
final class NotesMarkerParserTests: XCTestCase {
    func test_markerInSingleChunk_splitsTranslationAndNotes() {
        var parser = NotesMarkerParser()
        let (translation, notes) = parser.feed("Hello⟦NOTES⟧World")
        XCTAssertEqual(translation, "Hello")
        XCTAssertEqual(notes, "World")
    }

    func test_markerSplitAcrossChunks_atEveryPossiblePosition() {
        let marker = Array(NotesMarkerParser.marker)
        let prefix = "Hello "
        let suffix = " World"

        for splitIndex in 1..<marker.count {
            var parser = NotesMarkerParser()
            var translation = ""
            var notes = ""

            let firstChunk = prefix + String(marker[0..<splitIndex])
            let secondChunk = String(marker[splitIndex...]) + suffix

            let (t1, n1) = parser.feed(firstChunk)
            translation += t1; notes += n1
            let (t2, n2) = parser.feed(secondChunk)
            translation += t2; notes += n2
            let (t3, n3) = parser.finish()
            translation += t3; notes += n3

            XCTAssertEqual(translation, prefix, "split at \(splitIndex)")
            XCTAssertEqual(notes, suffix, "split at \(splitIndex)")
        }
    }

    func test_markerAbsent_wholeOutputIsTranslation() {
        let full = "Hello world, this is a translation without any marker."
        var parser = NotesMarkerParser()
        var translation = ""
        let (t1, n1) = parser.feed(full)
        translation += t1
        XCTAssertEqual(n1, "")
        let (t2, n2) = parser.finish()
        translation += t2
        XCTAssertEqual(n2, "")
        XCTAssertEqual(translation, full)
    }

    func test_markerPresent_emptyBlockUnderIt() {
        var parser = NotesMarkerParser()
        let (translation, notes) = parser.feed("Translation⟦NOTES⟧")
        XCTAssertEqual(translation, "Translation")
        XCTAssertEqual(notes, "")
        let (t2, n2) = parser.finish()
        XCTAssertEqual(t2, "")
        XCTAssertEqual(n2, "")
    }

    func test_textStartingWithBracket_thatIsNotTheRealMarker() {
        let full = "⟦NOT A MARKER⟧ actual text"
        var parser = NotesMarkerParser()
        var translation = ""
        let (t1, _) = parser.feed(full)
        translation += t1
        let (t2, _) = parser.finish()
        translation += t2
        XCTAssertEqual(translation, full)
    }

    func test_multipleDeltasAfterMarkerFound_allGoToNotes() {
        var parser = NotesMarkerParser()
        _ = parser.feed("Hi⟦NOTES⟧")
        let (t1, n1) = parser.feed("— note one\n")
        let (t2, n2) = parser.feed("— note two")
        XCTAssertEqual(t1, "")
        XCTAssertEqual(n1, "— note one\n")
        XCTAssertEqual(t2, "")
        XCTAssertEqual(n2, "— note two")
    }
}
