import XCTest
@testable import LLMTranslateKit

/// Раздел 11.5 ТЗ v1.2: 4 независимых бакета (текст/изображение × working/
/// strong), суммирование только реально пришедших от провайдера токенов,
/// «—» (nil) вместо самостоятельной оценки.
final class UsageCounterTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UsageCounterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_freshCounter_allBucketsEmpty() {
        let counter = UsageCounter(defaults: defaults)
        for summary in counter.currentMonthSummaries() {
            XCTAssertEqual(summary.requestCount, 0)
            XCTAssertNil(summary.inputTokens)
            XCTAssertNil(summary.outputTokens)
        }
    }

    func test_record_incrementsOnlyTheMatchingBucket() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .working, isImage: false, promptTokens: 10, completionTokens: 20)

        let summaries = counter.currentMonthSummaries()
        let touched = summaries.first { $0.slot == .working && !$0.isImage }
        let untouched = summaries.filter { $0.slot != .working || $0.isImage }

        XCTAssertEqual(touched?.requestCount, 1)
        XCTAssertEqual(touched?.inputTokens, 10)
        XCTAssertEqual(touched?.outputTokens, 20)
        for summary in untouched {
            XCTAssertEqual(summary.requestCount, 0)
        }
    }

    func test_record_accumulatesAcrossMultipleCalls() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .strong, isImage: true, promptTokens: 5, completionTokens: 7)
        counter.record(slot: .strong, isImage: true, promptTokens: 3, completionTokens: 2)

        let summary = counter.currentMonthSummaries().first { $0.slot == .strong && $0.isImage }
        XCTAssertEqual(summary?.requestCount, 2)
        XCTAssertEqual(summary?.inputTokens, 8)
        XCTAssertEqual(summary?.outputTokens, 9)
    }

    /// Раздел 11.5 ТЗ: «Если провайдер не отдаёт usage — прочерк, не оценка».
    func test_record_withoutTokenData_countsRequestButLeavesTokensNil() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .working, isImage: false, promptTokens: nil, completionTokens: nil)

        let summary = counter.currentMonthSummaries().first { $0.slot == .working && !$0.isImage }
        XCTAssertEqual(summary?.requestCount, 1)
        XCTAssertNil(summary?.inputTokens)
        XCTAssertNil(summary?.outputTokens)
    }

    func test_record_partialTokenData_stillMarksHasTokenData() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .working, isImage: false, promptTokens: 4, completionTokens: nil)

        let summary = counter.currentMonthSummaries().first { $0.slot == .working && !$0.isImage }
        XCTAssertEqual(summary?.inputTokens, 4)
        XCTAssertEqual(summary?.outputTokens, 0)
    }

    func test_reset_clearsCurrentMonth() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .working, isImage: false, promptTokens: 1, completionTokens: 1)
        counter.reset()

        for summary in counter.currentMonthSummaries() {
            XCTAssertEqual(summary.requestCount, 0)
            XCTAssertNil(summary.inputTokens)
        }
    }

    func test_allFourBuckets_areIndependentlyAddressable() {
        let counter = UsageCounter(defaults: defaults)
        counter.record(slot: .working, isImage: false, promptTokens: 1, completionTokens: 1)
        counter.record(slot: .working, isImage: true, promptTokens: 2, completionTokens: 2)
        counter.record(slot: .strong, isImage: false, promptTokens: 3, completionTokens: 3)
        counter.record(slot: .strong, isImage: true, promptTokens: 4, completionTokens: 4)

        let summaries = counter.currentMonthSummaries()
        XCTAssertEqual(summaries.count, 4)
        for summary in summaries {
            XCTAssertEqual(summary.requestCount, 1)
        }
    }
}
