import XCTest
@testable import LLMTranslateKit

/// Раздел 10.4 ТЗ: хендофф между интентом и приложением актуален только в
/// момент запуска команды. Остаток прошлого запуска не должен показываться
/// при открытии приложения с иконки.
final class PendingImageTranslationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(age: TimeInterval) throws -> URL {
        let url = directory.appendingPathComponent("handoff.dat")
        try Data("payload".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)],
            ofItemAtPath: url.path
        )
        return url
    }

    func test_freshFile_isReturnedAndDeleted() throws {
        let url = try makeFile(age: 2)
        XCTAssertEqual(PendingImageTranslation.takeFreshData(at: url), Data("payload".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_staleFile_isIgnoredButStillDeleted() throws {
        let url = try makeFile(age: PendingImageTranslation.handoffMaxAge + 60)
        XCTAssertNil(PendingImageTranslation.takeFreshData(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_missingFile_returnsNil() {
        let url = directory.appendingPathComponent("absent.dat")
        XCTAssertNil(PendingImageTranslation.takeFreshData(at: url))
    }

    func test_fileJustInsideLimit_isStillFresh() throws {
        let url = try makeFile(age: PendingImageTranslation.handoffMaxAge - 1)
        XCTAssertNotNil(PendingImageTranslation.takeFreshData(at: url))
    }
}
