import Foundation
import Security

/// Раздел 5 ТЗ. API-ключи — только в Keychain, с общей access group между
/// приложением и всеми расширениями. Ключ никогда не логируется и не
/// попадает в UserDefaults — это гарантируется тем, что других путей записи
/// ключа в этом типе просто нет.
public struct KeychainStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case osStatus(OSStatus)
        case unexpectedData
    }

    /// `$(AppIdentifierPrefix)com.<company>.llmtranslate.shared` — раздел 5 ТЗ.
    ///
    /// `nil` — не передавать `kSecAttrAccessGroup` в запросе вовсе и
    /// положиться на дефолтную access group приложения/расширения (первую
    /// из `keychain-access-groups` в entitlements). Такой запрос работает
    /// одинаково для приложения и расширения ровно потому, что оба таргета
    /// объявляют один и тот же единственный access group — не нужно знать
    /// заранее фактическое значение `$(AppIdentifierPrefix)`, которое
    /// зависит от команды разработчика и недоступно коду до подписи.
    public let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    // Раздел 5 ТЗ v1.2: ключ адресуется по слоту (`working`/`strong`), не по
    // провайдеру — слот однозначно определяет, какой ключ имеется в виду,
    // даже если пользователь сменит провайдера внутри слота.
    private func service(for slot: SlotID) -> String {
        "com.tyrex.llmtranslate.apikey.\(slot.rawValue)"
    }

    private func baseQuery(for slot: SlotID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: slot),
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func setAPIKey(_ key: String, slot: SlotID) throws {
        // Раздел 5 ТЗ: сначала удалить существующую запись, затем вставить
        // новую — SecItemUpdate не даёт поменять kSecAttrAccessible задним
        // числом так же надёжно, как add-после-delete.
        SecItemDelete(baseQuery(for: slot) as CFDictionary)

        var attributes = baseQuery(for: slot)
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.osStatus(status) }
    }

    /// `nil`, если ключ не задан. Никогда не возвращает пустую строку как "нет ключа".
    public func apiKey(slot: SlotID) throws -> String? {
        var query = baseQuery(for: slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.osStatus(status) }
        guard let data = result as? Data else { throw StoreError.unexpectedData }
        return String(decoding: data, as: UTF8.self)
    }

    public func deleteAPIKey(slot: SlotID) throws {
        let status = SecItemDelete(baseQuery(for: slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.osStatus(status)
        }
    }

    /// Маска для отображения в UI после сохранения — раздел 5 ТЗ: «показывать
    /// маску sk-…3f9a». Чистая функция, ключ в открытом виде на входе и
    /// только на входе.
    public static func maskedPreview(_ key: String) -> String {
        guard key.count > 6 else { return String(repeating: "•", count: max(key.count, 4)) }
        let prefix = key.prefix(3)
        let suffix = key.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
