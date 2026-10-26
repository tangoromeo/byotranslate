import Foundation
import CryptoKit

/// Раздел 11.4 ТЗ v1.2. Одна запись кэша.
struct CachedTranslation: Codable, Sendable {
    let translation: String
    let notes: [String]
    let createdAt: Date
    var lastAccessedAt: Date
    /// Только у фрагментов скриншота: маска надписи (`CropFingerprint`) и
    /// контекст (язык, модель, промпт) — для поиска «почти той же» надписи.
    /// Маска — по сути читаемая картинка текста, поэтому живёт только здесь,
    /// в зашифрованном файле, с тем же сроком и вытеснением.
    var regionWidth: Int? = nil
    var regionMask: Data? = nil
    var regionContext: String? = nil
}

/// Запрос к кэшу фрагментов: точный ключ и маска для поиска похожих.
public struct RegionCacheQuery: Sendable {
    public let key: String
    public let signature: CropFingerprint.Signature

    public init(key: String, signature: CropFingerprint.Signature) {
        self.key = key
        self.signature = signature
    }
}

/// Раздел 11.4 ТЗ v1.2: «По умолчанию выключен... не экономию денег, а
/// нулевую латентность на повторе». Один зашифрованный файл в App Group —
/// не база данных, оправдано потолком в 200 записей/2 МБ (раздел явно
/// рассчитан на то, что весь файл перечитывается и переписывается целиком).
public final class TranslationCache: @unchecked Sendable {
    private let appGroupSuiteName: String
    private let keychain: KeychainStore

    static let ttl: TimeInterval = 24 * 60 * 60
    /// Было 200; с кэшем фрагментов скриншота (пункты меню — короткие строки,
    /// десятки на экран) поднят до 1000. Общий предел по объёму прежний.
    static let maxEntries = 1000
    static let maxBytes = 2 * 1024 * 1024

    public init(appGroupSuiteName: String, keychain: KeychainStore = KeychainStore()) {
        self.appGroupSuiteName = appGroupSuiteName
        self.keychain = keychain
    }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent("translation-cache.enc")
    }

    /// `nil` — либо не в кэше, либо истёк TTL. Обновляет `lastAccessedAt`
    /// (раздел 11.4 ТЗ: «LRU»).
    public func get(key: String) -> (translation: String, notes: [String])? {
        var store = loadStore()
        guard var entry = store[key] else { return nil }
        guard Date().timeIntervalSince(entry.createdAt) < Self.ttl else {
            store.removeValue(forKey: key)
            saveStore(store)
            return nil
        }
        entry.lastAccessedAt = Date()
        store[key] = entry
        saveStore(store)
        return (entry.translation, entry.notes)
    }

    /// Пакетное чтение (кэш фрагментов: десятки ключей за раз) — файл
    /// расшифровывается и сохраняется один раз, а не на каждый ключ.
    public func translations(for keys: [String]) -> [String: String] {
        var store = loadStore()
        let now = Date()
        var found: [String: String] = [:]
        var changed = false
        for key in keys {
            guard var entry = store[key] else { continue }
            if now.timeIntervalSince(entry.createdAt) >= Self.ttl {
                store.removeValue(forKey: key)
            } else {
                entry.lastAccessedAt = now
                store[key] = entry
                found[key] = entry.translation
            }
            changed = true
        }
        if changed { saveStore(store) }
        return found
    }

    /// Фрагменты скриншота: точный ключ, а если его нет — сохранённая надпись
    /// того же контекста с «почти той же» маской (`CropFingerprint.isSameText`).
    /// Результат — ключ запроса → перевод. Файл читается и пишется один раз.
    public func regionTranslations(for queries: [RegionCacheQuery], context: String) -> [String: String] {
        guard !queries.isEmpty else { return [:] }
        var store = loadStore()
        let now = Date()
        let fresh = store.filter { now.timeIntervalSince($0.value.createdAt) < Self.ttl }
        let candidates = fresh.compactMap { key, entry -> (String, CropFingerprint.Signature)? in
            guard entry.regionContext == context, let width = entry.regionWidth, let mask = entry.regionMask else { return nil }
            return (key, CropFingerprint.Signature(width: width, mask: mask))
        }
        var found: [String: String] = [:]
        for query in queries {
            let hitKey: String?
            if fresh[query.key] != nil {
                hitKey = query.key
            } else {
                hitKey = candidates.first { CropFingerprint.isSameText($0.1, query.signature) }?.0
            }
            guard let hitKey, var entry = store[hitKey] else { continue }
            entry.lastAccessedAt = now
            store[hitKey] = entry
            found[query.key] = entry.translation
        }
        if store.count != fresh.count || !found.isEmpty {
            store = store.filter { now.timeIntervalSince($0.value.createdAt) < Self.ttl }
            saveStore(store)
        }
        return found
    }

    /// Пакетная запись переводов фрагментов вместе с их масками.
    public func setRegionTranslations(_ items: [(query: RegionCacheQuery, translation: String)], context: String) {
        guard !items.isEmpty else { return }
        var store = loadStore()
        let now = Date()
        for item in items {
            var entry = CachedTranslation(translation: item.translation, notes: [], createdAt: now, lastAccessedAt: now)
            entry.regionWidth = item.query.signature.width
            entry.regionMask = item.query.signature.mask
            entry.regionContext = context
            store[item.query.key] = entry
        }
        evictIfNeeded(&store)
        saveStore(store)
    }

    public func set(key: String, translation: String, notes: [String]) {
        var store = loadStore()
        let now = Date()
        store[key] = CachedTranslation(translation: translation, notes: notes, createdAt: now, lastAccessedAt: now)
        evictIfNeeded(&store)
        saveStore(store)
    }

    /// Раздел 11.4 ТЗ: «Кэш полностью очищается при смене любого слота,
    /// модели или системного промпта» — а также кнопкой «Очистить кэш».
    public func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public var currentSizeBytes: Int {
        guard let url = fileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int
        else { return 0 }
        return size
    }

    // MARK: - Private

    /// Раздел 11.4 ТЗ: «TTL 24 часа. LRU, потолок 200 записей и 2 МБ, что меньше».
    private func evictIfNeeded(_ store: inout [String: CachedTranslation]) {
        let now = Date()
        store = store.filter { now.timeIntervalSince($0.value.createdAt) < Self.ttl }

        while store.count > Self.maxEntries {
            guard let oldestKey = store.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key else { break }
            store.removeValue(forKey: oldestKey)
        }
        while let encoded = try? JSONEncoder().encode(store), encoded.count > Self.maxBytes, !store.isEmpty {
            guard let oldestKey = store.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key else { break }
            store.removeValue(forKey: oldestKey)
        }
    }

    private func loadStore() -> [String: CachedTranslation] {
        guard let url = fileURL, let encryptedData = try? Data(contentsOf: url) else { return [:] }
        guard let keyData = try? keychain.cacheEncryptionKeyData() else { return [:] }
        let key = SymmetricKey(data: keyData)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
              let decrypted = try? AES.GCM.open(sealedBox, using: key)
        else { return [:] }
        return (try? JSONDecoder().decode([String: CachedTranslation].self, from: decrypted)) ?? [:]
    }

    private func saveStore(_ store: [String: CachedTranslation]) {
        guard let url = fileURL, let keyData = try? keychain.cacheEncryptionKeyData() else { return }
        let key = SymmetricKey(data: keyData)
        guard let plain = try? JSONEncoder().encode(store),
              let sealedBox = try? AES.GCM.seal(plain, using: key),
              let combined = sealedBox.combined
        else { return }
        try? combined.write(to: url, options: .atomic)
    }
}
