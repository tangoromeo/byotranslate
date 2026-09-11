import Foundation

/// Раздел 13.5 ТЗ v1.2: «лог последних 20 запросов без ключей, без
/// исходных текстов и без изображений (только: слот, провайдер, модель,
/// тип ввода, режим, размер, латентность, статус, usage)». Структура
/// физически не может нести текст/ключ — таких полей у неё просто нет.
public struct RequestLogEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let slot: SlotID
    public let providerID: ProviderID
    public let model: String
    public let isImage: Bool
    public let mode: TranslationMode
    public let payloadSizeBytes: Int
    public let latencyMs: Int
    /// "success" или код/тег ошибки — никогда текст ошибки провайдера
    /// целиком (в нём мог бы просочиться фрагмент исходного текста).
    public let status: String
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        slot: SlotID,
        providerID: ProviderID,
        model: String,
        isImage: Bool,
        mode: TranslationMode,
        payloadSizeBytes: Int,
        latencyMs: Int,
        status: String,
        promptTokens: Int?,
        completionTokens: Int?
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.providerID = providerID
        self.model = model
        self.isImage = isImage
        self.mode = mode
        self.payloadSizeBytes = payloadSizeBytes
        self.latencyMs = latencyMs
        self.status = status
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Кольцевой буфер на 20 записей в App Group `UserDefaults`, тот же
/// паттерн, что `UsageCounter`. Новые записи — в начале списка.
public final class RequestLog: @unchecked Sendable {
    public static let maxEntries = 20
    private static let storageKey = "requestLog"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public init?(appGroupSuiteName: String) {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName) else { return nil }
        self.defaults = defaults
    }

    public func record(_ entry: RequestLogEntry) {
        var entries = recentEntries()
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func recentEntries() -> [RequestLogEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([RequestLogEntry].self, from: data)) ?? []
    }

    public func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
