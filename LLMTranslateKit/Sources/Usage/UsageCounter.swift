import Foundation

struct UsageBucket: Codable, Sendable {
    var requestCount = 0
    var inputTokens = 0
    var outputTokens = 0
    /// Раздел 11.5 ТЗ: «Если провайдер не отдаёт usage — показывать прочерк
    /// для этой строки. Не оценивать токены самостоятельно» — отличает
    /// «0 токенов» от «неизвестно».
    var hasTokenData = false
}

private struct UsageMonthData: Codable, Sendable {
    var textWorking = UsageBucket()
    var textStrong = UsageBucket()
    var imageWorking = UsageBucket()
    var imageStrong = UsageBucket()
}

/// Раздел 11.5 ТЗ v1.2: локальный счётчик расхода за текущий календарный
/// месяц, без лимитов и блокировок, никуда не отправляется.
public final class UsageCounter: @unchecked Sendable {
    public struct Summary: Sendable {
        public let slot: SlotID
        public let isImage: Bool
        public let requestCount: Int
        /// `nil` — провайдер ни разу не отдал usage для этой комбинации.
        public let inputTokens: Int?
        public let outputTokens: Int?
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public init?(appGroupSuiteName: String) {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName) else { return nil }
        self.defaults = defaults
    }

    /// Раздел 11.5 ТЗ: считать только реально выполненные запросы — попадания
    /// в кэш (раздел 11.4) сюда не попадают, реального обращения к провайдеру
    /// не было.
    public func record(slot: SlotID, isImage: Bool, promptTokens: Int?, completionTokens: Int?) {
        var data = loadCurrentMonth()
        var bucket = bucket(for: slot, isImage: isImage, in: data)
        bucket.requestCount += 1
        if let promptTokens {
            bucket.inputTokens += promptTokens
            bucket.hasTokenData = true
        }
        if let completionTokens {
            bucket.outputTokens += completionTokens
            bucket.hasTokenData = true
        }
        setBucket(bucket, for: slot, isImage: isImage, in: &data)
        saveCurrentMonth(data)
    }

    public func currentMonthSummaries() -> [Summary] {
        let data = loadCurrentMonth()
        return [
            summary(slot: .working, isImage: false, bucket: data.textWorking),
            summary(slot: .working, isImage: true, bucket: data.imageWorking),
            summary(slot: .strong, isImage: false, bucket: data.textStrong),
            summary(slot: .strong, isImage: true, bucket: data.imageStrong),
        ]
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey(for: Self.currentMonthTag()))
    }

    // MARK: - Private

    private func summary(slot: SlotID, isImage: Bool, bucket: UsageBucket) -> Summary {
        Summary(
            slot: slot,
            isImage: isImage,
            requestCount: bucket.requestCount,
            inputTokens: bucket.hasTokenData ? bucket.inputTokens : nil,
            outputTokens: bucket.hasTokenData ? bucket.outputTokens : nil
        )
    }

    private func bucket(for slot: SlotID, isImage: Bool, in data: UsageMonthData) -> UsageBucket {
        if slot == .working {
            return isImage ? data.imageWorking : data.textWorking
        } else {
            return isImage ? data.imageStrong : data.textStrong
        }
    }

    private func setBucket(_ bucket: UsageBucket, for slot: SlotID, isImage: Bool, in data: inout UsageMonthData) {
        if slot == .working {
            if isImage { data.imageWorking = bucket } else { data.textWorking = bucket }
        } else {
            if isImage { data.imageStrong = bucket } else { data.textStrong = bucket }
        }
    }

    private static func currentMonthTag() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private static func storageKey(for monthTag: String) -> String {
        "usageCounter.\(monthTag)"
    }

    private func loadCurrentMonth() -> UsageMonthData {
        guard let data = defaults.data(forKey: Self.storageKey(for: Self.currentMonthTag())) else {
            return UsageMonthData()
        }
        return (try? JSONDecoder().decode(UsageMonthData.self, from: data)) ?? UsageMonthData()
    }

    private func saveCurrentMonth(_ data: UsageMonthData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        defaults.set(encoded, forKey: Self.storageKey(for: Self.currentMonthTag()))
    }
}
