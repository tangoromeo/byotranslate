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
        baseQuery(forRawService: service(for: slot))
    }

    private func baseQuery(forRawService serviceName: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
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

    // MARK: - Ключи профилей (раздел B5)

    // Профиль подключения хранит ключ один раз; слоты ссылаются на профиль.
    private func service(for profile: UUID) -> String {
        "com.tyrex.llmtranslate.apikey.profile.\(profile.uuidString)"
    }

    public func setAPIKey(_ key: String, profile: UUID) throws {
        let query = baseQuery(forRawService: service(for: profile))
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.osStatus(status) }
    }

    public func apiKey(profile: UUID) throws -> String? {
        var query = baseQuery(forRawService: service(for: profile))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.osStatus(status) }
        guard let data = result as? Data else { throw StoreError.unexpectedData }
        return String(decoding: data, as: UTF8.self)
    }

    public func deleteAPIKey(profile: UUID) throws {
        let status = SecItemDelete(baseQuery(forRawService: service(for: profile)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.osStatus(status)
        }
    }

    // MARK: - Ключ шифрования кэша (раздел 5/11.4 ТЗ v1.2)

    private static let cacheEncryptionKeyService = "com.tyrex.llmtranslate.cache-encryption-key"

    /// Отдельная запись в Keychain, та же access group — «Ключ шифрования
    /// кэша (раздел 11.4) хранится там же, отдельной записью» (раздел 5 ТЗ).
    /// Генерируется лениво при первом обращении и переживает переустановку
    /// в рамках одного access group (как и API-ключи).
    public func cacheEncryptionKeyData() throws -> Data {
        let query = baseQuery(forRawService: Self.cacheEncryptionKeyService)
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        guard status == errSecItemNotFound else { throw StoreError.osStatus(status) }

        var newKeyData = Data(count: 32) // AES-256
        let genStatus = newKeyData.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, 32, pointer.baseAddress!)
        }
        guard genStatus == errSecSuccess else { throw StoreError.osStatus(genStatus) }

        var attributes = query
        attributes[kSecValueData as String] = newKeyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.osStatus(addStatus) }
        return newKeyData
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
