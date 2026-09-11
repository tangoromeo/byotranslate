import XCTest
@testable import LLMTranslateKit

/// Раздел 13.5 ТЗ v1.2: кольцевой буфер на 20 записей, только метаданные.
final class RequestLogTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RequestLogTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeEntry(status: String = "success") -> RequestLogEntry {
        RequestLogEntry(
            slot: .working,
            providerID: .openAICompatible,
            model: "gpt-5",
            isImage: false,
            mode: .plain,
            payloadSizeBytes: 42,
            latencyMs: 100,
            status: status,
            promptTokens: 10,
            completionTokens: 20
        )
    }

    func test_freshLog_isEmpty() {
        XCTAssertTrue(RequestLog(defaults: defaults).recentEntries().isEmpty)
    }

    func test_record_addsEntry() {
        let log = RequestLog(defaults: defaults)
        log.record(makeEntry())
        XCTAssertEqual(log.recentEntries().count, 1)
    }

    func test_record_newestFirst() {
        let log = RequestLog(defaults: defaults)
        log.record(makeEntry(status: "first"))
        log.record(makeEntry(status: "second"))
        XCTAssertEqual(log.recentEntries().map(\.status), ["second", "first"])
    }

    func test_record_capsAtTwentyEntries_evictingOldest() {
        let log = RequestLog(defaults: defaults)
        for i in 0..<25 {
            log.record(makeEntry(status: "\(i)"))
        }
        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, RequestLog.maxEntries)
        // Самая новая запись (24) первая, самые старые (0-4) вытеснены.
        XCTAssertEqual(entries.first?.status, "24")
        XCTAssertFalse(entries.map(\.status).contains("0"))
        XCTAssertFalse(entries.map(\.status).contains("4"))
    }

    func test_clear_removesAllEntries() {
        let log = RequestLog(defaults: defaults)
        log.record(makeEntry())
        log.clear()
        XCTAssertTrue(log.recentEntries().isEmpty)
    }
}
