import Foundation

/// Раздел B5: до профилей каждый слот хранил провайдера, адрес и собственный
/// ключ. Миграция превращает настроенные слоты в профили, не теряя ключей:
/// слот со своим ключом получает профиль и ссылку на него. Если два слота
/// ведут на один и тот же пресет с разными ключами, второй остаётся по-старому
/// (сеть при этом работает: `connection(for:)` откатывается на поля слота).
///
/// Ключи читаются и пишутся через замыкания, чтобы миграцию можно было
/// проверить без Keychain.
public enum ProfileMigration {
    public struct KeyAccess {
        public var slotKey: (SlotID) -> String?
        public var profileKey: (UUID) -> String?
        public var setProfileKey: (String, UUID) -> Void

        public init(
            slotKey: @escaping (SlotID) -> String?,
            profileKey: @escaping (UUID) -> String?,
            setProfileKey: @escaping (String, UUID) -> Void
        ) {
            self.slotKey = slotKey
            self.profileKey = profileKey
            self.setProfileKey = setProfileKey
        }

        public static func keychain(_ store: KeychainStore) -> KeyAccess {
            KeyAccess(
                slotKey: { (try? store.apiKey(slot: $0)) ?? nil },
                profileKey: { (try? store.apiKey(profile: $0)) ?? nil },
                setProfileKey: { try? store.setAPIKey($0, profile: $1) }
            )
        }
    }

    /// Идемпотентна: повторный вызов ничего не делает.
    public static func run(settings: LLMTranslateSettings, keys: KeyAccess) {
        guard !settings.profilesMigrated else { return }
        for slotID in [SlotID.working, SlotID.strong] {
            let config = settings.slot(slotID)
            guard config.profileID == nil, config.isConfigured,
                  let key = keys.slotKey(slotID), !key.isEmpty
            else { continue }

            let preset = ProfilePreset.infer(providerID: config.providerID, baseURL: config.baseURL)
            if let existing = settings.connectionProfiles.first(where: { $0.preset == preset }) {
                // Тот же пресет: переиспользуем профиль, только если ключ тот же.
                if keys.profileKey(existing.id) == key { config.profileID = existing.id }
                continue
            }
            let profile = ConnectionProfile(preset: preset, providerID: config.providerID, baseURL: config.baseURL)
            keys.setProfileKey(key, profile.id)
            settings.upsert(profile)
            config.profileID = profile.id
        }
        settings.profilesMigrated = true
    }
}
