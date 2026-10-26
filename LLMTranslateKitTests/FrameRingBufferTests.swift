import XCTest
@testable import LLMTranslateKit

/// B8: кольцо кадров трансляции экрана.
final class FrameRingBufferTests: XCTestCase {
    private var directory: URL!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FrameRingBufferTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func buffer(capacity: Int = 4) -> FrameRingBuffer {
        FrameRingBuffer(directory: directory, capacity: capacity)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    func test_fileName_roundTripsAndSortsChronologically() {
        let early = FrameRingBuffer.fileName(for: at(1))
        let late = FrameRingBuffer.fileName(for: at(100))
        XCTAssertLessThan(early, late)
        XCTAssertEqual(FrameRingBuffer.date(fromFileName: early)!.timeIntervalSince1970, at(1).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(FrameRingBuffer.date(fromFileName: "notes.txt"))
        XCTAssertNil(FrameRingBuffer.date(fromFileName: "abc.jpg"))
    }

    func test_write_keepsOnlyNewestCapacityFrames() throws {
        let ring = buffer(capacity: 3)
        for i in 0..<6 { try ring.write(Data([UInt8(i)]), at: at(Double(i))) }
        let frames = ring.allFrames()
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map { $0.date.timeIntervalSince(base) }.map { Int($0.rounded()) }, [3, 4, 5])
    }

    func test_frame_picksNewestFrameBeforeTheTap() throws {
        let ring = buffer()
        for i in 0..<4 { try ring.write(Data([UInt8(i)]), at: at(Double(i))) } // 0,1,2,3 с
        // тап в 3,5 с, отступ 0,8 → граница 2,7 → берём кадр 2 с, а не 3 с (экран уже мог смениться)
        let picked = ring.frame(now: at(3.5), lag: 0.8)
        XCTAssertEqual(Int(picked!.date.timeIntervalSince(base).rounded()), 2)
    }

    func test_frame_fallsBackToOldest_whenBroadcastJustStarted() throws {
        let ring = buffer()
        try ring.write(Data([1]), at: at(10))
        try ring.write(Data([2]), at: at(10.7))
        // тап через 0,3 с после первого кадра: все кадры «слишком свежие» — берём самый старый
        XCTAssertEqual(Int(ring.frame(now: at(10.3), lag: 0.8)!.date.timeIntervalSince(base).rounded()), 10)
    }

    func test_frame_ignoresStaleFrames_broadcastProbablyStopped() throws {
        let ring = buffer()
        try ring.write(Data([1]), at: at(0))
        XCTAssertNil(ring.frame(now: at(31), maxAge: 30))
        XCTAssertNotNil(ring.frame(now: at(29), maxAge: 30))
    }

    func test_frame_emptyOrMissingDirectory_returnsNil() {
        XCTAssertNil(buffer().frame(now: base))
        XCTAssertNil(buffer().data(now: base))
    }

    func test_data_returnsBytesOfChosenFrame() throws {
        let ring = buffer()
        try ring.write(Data([7, 7, 7]), at: at(0))
        try ring.write(Data([9]), at: at(2))
        XCTAssertEqual(ring.data(now: at(2.5), lag: 0.8), Data([7, 7, 7]))
    }

    func test_removeAll_clearsFramesButNotForeignFiles() throws {
        let ring = buffer()
        try ring.write(Data([1]), at: at(0))
        let foreign = directory.appendingPathComponent("keep.txt")
        try Data([1]).write(to: foreign)
        ring.removeAll()
        XCTAssertTrue(ring.allFrames().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func test_foreignFilesAreIgnoredInSelection() throws {
        let ring = buffer()
        try ring.write(Data([1]), at: at(0))
        try Data([1]).write(to: directory.appendingPathComponent("zzz.jpg"))
        XCTAssertEqual(ring.allFrames().count, 1)
    }
}
