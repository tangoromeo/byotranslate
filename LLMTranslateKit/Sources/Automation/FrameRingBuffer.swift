import Foundation

/// B8: кольцо последних кадров трансляции экрана в папке App Group.
/// Расширение трансляции кладёт сюда сжатые кадры (несколько штук в секунду
/// не нужно — хватает одного за 0,7 с), приложение по нажатию на PiP берёт
/// кадр, снятый чуть ДО нажатия: в момент нажатия на экране уже наше
/// приложение, а не то, что пользователь хотел перевести.
///
/// Только Foundation и внедряемое время: этот файл компилируется и в Kit, и
/// напрямую в расширение трансляции (там Kit не линкуется из-за лимита памяти
/// ~50 МБ), и тестируется в SPM-харнессе.
public struct FrameRingBuffer: Sendable {
    public struct Frame: Sendable, Equatable {
        public let url: URL
        public let date: Date
    }

    public let directory: URL
    public let capacity: Int

    public init(directory: URL, capacity: Int = 4) {
        self.directory = directory
        self.capacity = max(1, capacity)
    }

    // MARK: - Имена файлов

    /// «0001790943081123.jpg»: миллисекунды с 1970 года с нулями слева —
    /// лексикографический порядок совпадает с хронологическим.
    public static func fileName(for date: Date) -> String {
        let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded())
        return String(format: "%016ld.jpg", milliseconds)
    }

    public static func date(fromFileName name: String) -> Date? {
        guard name.hasSuffix(".jpg"), let milliseconds = Int(name.dropLast(4)) else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    // MARK: - Запись

    /// Атомарно пишет кадр и удаляет лишние старые.
    public func write(_ data: Data, at date: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(Self.fileName(for: date)), options: .atomic)
        prune()
    }

    /// Оставляет `capacity` самых новых кадров.
    public func prune() {
        let frames = allFrames()
        guard frames.count > capacity else { return }
        for frame in frames.dropLast(capacity) {
            try? FileManager.default.removeItem(at: frame.url)
        }
    }

    /// Удаляет все кадры (конец трансляции): снимки экрана не должны
    /// оставаться на диске дольше, чем идёт трансляция.
    public func removeAll() {
        for frame in allFrames() {
            try? FileManager.default.removeItem(at: frame.url)
        }
    }

    // MARK: - Чтение

    /// Все кадры от старого к новому; посторонние файлы игнорируются.
    public func allFrames() -> [Frame] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .compactMap { url in Self.date(fromFileName: url.lastPathComponent).map { Frame(url: url, date: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Кадр для перевода по нажатию в момент `now`:
    /// - самый новый кадр не позже `now - lag` (экран до нажатия);
    /// - если таких нет (трансляция только началась) — самый старый из имеющихся;
    /// - кадры старше `maxAge` не берутся: трансляция, скорее всего, остановлена.
    public func frame(now: Date, lag: TimeInterval = 0.8, maxAge: TimeInterval = 30) -> Frame? {
        let fresh = allFrames().filter { now.timeIntervalSince($0.date) <= maxAge }
        let cutoff = now.addingTimeInterval(-lag)
        return fresh.last { $0.date <= cutoff } ?? fresh.first
    }

    public func data(now: Date, lag: TimeInterval = 0.8, maxAge: TimeInterval = 30) -> Data? {
        frame(now: now, lag: lag, maxAge: maxAge).flatMap { try? Data(contentsOf: $0.url) }
    }
}
