import XCTest
@testable import LLMTranslateKit

/// B5: профили подключения, разрешение подключения слота и миграция слотов.
final class ConnectionProfileTests: XCTestCase {
    private func makeSettings() -> LLMTranslateSettings {
        let suite = "ConnectionProfileTests.\(UUID().uuidString)"
        return LLMTranslateSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    private final class FakeKeys {
        var slots: [SlotID: String] = [:]
        var profiles: [UUID: String] = [:]
        var access: ProfileMigration.KeyAccess {
            .init(
                slotKey: { self.slots[$0] },
                profileKey: { self.profiles[$0] },
                setProfileKey: { self.profiles[$1] = $0 }
            )
        }
    }

    // MARK: - Пресеты

    func test_presets_haveProviderAndURL_exceptCustom() {
        for preset in ProfilePreset.allCases where preset != .custom {
            XCTAssertNotNil(preset.providerID, "\(preset)")
            XCTAssertNotNil(preset.defaultBaseURL, "\(preset)")
        }
        XCTAssertNil(ProfilePreset.custom.providerID)
        XCTAssertNil(ProfilePreset.custom.defaultBaseURL)
    }

    func test_make_custom_requiresProviderAndURL() {
        XCTAssertNil(ConnectionProfile.make(preset: .custom))
        let url = URL(string: "http://localhost:11434/v1")!
        let profile = ConnectionProfile.make(preset: .custom, providerID: .openAICompatible, baseURL: url)
        XCTAssertEqual(profile?.baseURL, url)
    }

    func test_make_openRouter_usesOpenAICompatibleAtOpenRouterHost() {
        let profile = ConnectionProfile.make(preset: .openRouter)
        XCTAssertEqual(profile?.providerID, .openAICompatible)
        XCTAssertEqual(profile?.baseURL.host, "openrouter.ai")
    }

    func test_infer_recognizesKnownHosts() {
        XCTAssertEqual(ProfilePreset.infer(providerID: .openAICompatible, baseURL: OpenAICompatibleProvider.defaultBaseURL), .openAI)
        XCTAssertEqual(ProfilePreset.infer(providerID: .openAICompatible, baseURL: URL(string: "https://openrouter.ai/api/v1")!), .openRouter)
        XCTAssertEqual(ProfilePreset.infer(providerID: .anthropic, baseURL: AnthropicProvider.defaultBaseURL), .anthropic)
        XCTAssertEqual(ProfilePreset.infer(providerID: .googleGemini, baseURL: GeminiProvider.defaultBaseURL), .google)
        XCTAssertEqual(ProfilePreset.infer(providerID: .openAICompatible, baseURL: URL(string: "http://localhost:11434/v1")!), .custom)
    }

    // MARK: - Коллекция профилей

    func test_upsert_addsThenUpdatesById() {
        let settings = makeSettings()
        var profile = ConnectionProfile.make(preset: .openAI)!
        settings.upsert(profile)
        profile.baseURL = URL(string: "https://proxy.example/v1")!
        settings.upsert(profile)
        XCTAssertEqual(settings.connectionProfiles.count, 1)
        XCTAssertEqual(settings.profile(id: profile.id)?.baseURL.host, "proxy.example")
    }

    func test_removeProfile_clearsSlotsThatUsedIt_andKeepsOthers() {
        let settings = makeSettings()
        let removed = ConnectionProfile.make(preset: .openAI)!
        let kept = ConnectionProfile.make(preset: .anthropic)!
        settings.upsert(removed)
        settings.upsert(kept)
        settings.slot(.working).profileID = removed.id
        settings.slot(.working).model = "gpt"
        settings.slot(.strong).profileID = kept.id
        settings.slot(.strong).model = "claude"

        settings.removeProfile(id: removed.id, keychain: KeychainStore())

        XCTAssertEqual(settings.connectionProfiles.map(\.id), [kept.id])
        XCTAssertNil(settings.slot(.working).profileID)
        XCTAssertFalse(settings.slot(.working).isConfigured)
        XCTAssertEqual(settings.slot(.strong).profileID, kept.id)
        XCTAssertTrue(settings.slot(.strong).isConfigured)
    }

    // MARK: - Разрешение подключения слота

    func test_connection_withoutProfile_fallsBackToSlotFields() {
        let settings = makeSettings()
        settings.slot(.working).providerID = .anthropic
        settings.slot(.working).baseURL = AnthropicProvider.defaultBaseURL
        let connection = settings.connection(for: .working, keychain: KeychainStore())
        XCTAssertEqual(connection.providerID, .anthropic)
        XCTAssertEqual(connection.baseURL, AnthropicProvider.defaultBaseURL)
    }

    func test_connection_withProfile_usesProfileProviderAndURL() {
        let settings = makeSettings()
        let profile = ConnectionProfile.make(preset: .openRouter)!
        settings.upsert(profile)
        settings.slot(.strong).profileID = profile.id
        // поля самого слота профиль перекрывает
        settings.slot(.strong).providerID = .anthropic
        let connection = settings.connection(for: .strong, keychain: KeychainStore())
        XCTAssertEqual(connection.providerID, .openAICompatible)
        XCTAssertEqual(connection.baseURL.host, "openrouter.ai")
    }

    func test_connection_profileMissing_fallsBackToSlot() {
        let settings = makeSettings()
        settings.slot(.working).profileID = UUID() // профиля с таким id нет
        settings.slot(.working).providerID = .googleGemini
        XCTAssertEqual(settings.connection(for: .working, keychain: KeychainStore()).providerID, .googleGemini)
    }

    // MARK: - Миграция

    func test_migration_turnsConfiguredSlotsIntoProfiles_keepingKeys() {
        let settings = makeSettings()
        let keys = FakeKeys()
        settings.slot(.working).providerID = .openAICompatible
        settings.slot(.working).baseURL = URL(string: "https://openrouter.ai/api/v1")!
        settings.slot(.working).model = "a/b"
        settings.slot(.strong).providerID = .anthropic
        settings.slot(.strong).baseURL = AnthropicProvider.defaultBaseURL
        settings.slot(.strong).model = "claude"
        keys.slots = [.working: "sk-or", .strong: "sk-ant"]

        ProfileMigration.run(settings: settings, keys: keys.access)

        XCTAssertEqual(settings.connectionProfiles.map(\.preset), [.openRouter, .anthropic])
        let working = settings.slot(.working).profileID!
        let strong = settings.slot(.strong).profileID!
        XCTAssertEqual(keys.profiles[working], "sk-or")
        XCTAssertEqual(keys.profiles[strong], "sk-ant")
        XCTAssertTrue(settings.profilesMigrated)
    }

    func test_migration_twoSlotsSamePresetSameKey_shareOneProfile() {
        let settings = makeSettings()
        let keys = FakeKeys()
        for slot in [SlotID.working, .strong] {
            settings.slot(slot).baseURL = URL(string: "https://openrouter.ai/api/v1")!
            settings.slot(slot).model = "m-\(slot.rawValue)"
            keys.slots[slot] = "same"
        }
        ProfileMigration.run(settings: settings, keys: keys.access)
        XCTAssertEqual(settings.connectionProfiles.count, 1)
        XCTAssertEqual(settings.slot(.working).profileID, settings.slot(.strong).profileID)
    }

    func test_migration_twoSlotsSamePresetDifferentKeys_secondStaysLegacy() {
        let settings = makeSettings()
        let keys = FakeKeys()
        for (slot, key) in [(SlotID.working, "k1"), (.strong, "k2")] {
            settings.slot(slot).baseURL = URL(string: "https://openrouter.ai/api/v1")!
            settings.slot(slot).model = "m"
            keys.slots[slot] = key
        }
        ProfileMigration.run(settings: settings, keys: keys.access)
        XCTAssertEqual(settings.connectionProfiles.count, 1)
        XCTAssertNotNil(settings.slot(.working).profileID)
        XCTAssertNil(settings.slot(.strong).profileID, "ключ k2 остаётся у слота, а не теряется")
    }

    func test_migration_skipsUnconfiguredSlots_andIsIdempotent() {
        let settings = makeSettings()
        let keys = FakeKeys()
        keys.slots[.working] = "sk" // ключ есть, модели нет
        ProfileMigration.run(settings: settings, keys: keys.access)
        XCTAssertTrue(settings.connectionProfiles.isEmpty)

        // после флага повторный запуск ничего не меняет даже при новых данных
        settings.slot(.working).model = "m"
        ProfileMigration.run(settings: settings, keys: keys.access)
        XCTAssertTrue(settings.connectionProfiles.isEmpty)
    }
}
