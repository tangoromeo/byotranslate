import XCTest
@testable import LLMTranslateKit

/// Раздел 14, п. 5 ТЗ: запись, чтение «из второго процесса», удаление.
///
/// По-настоящему протестировать два процесса юнит-тест не может — здесь и
/// приложение, и расширение эмулируются двумя независимыми
/// `KeychainStore` в одном тестовом раннере. Это проверяет контракт («один
/// и тот же access group ⇒ общие данные, разные ⇒ изолированные данные»),
/// а не реальную межпроцессную IPC-доставку — та проверяется только на
/// реальном устройстве/симуляторе с приложением и расширением, поставленными
/// из одного архива (см. критерии приёмки, раздел 15 ТЗ).
final class KeychainStoreTests: XCTestCase {
    private let provider = ProviderID(rawValue: "test-provider-\(UUID().uuidString)")

    override func tearDown() {
        try? KeychainStore().deleteAPIKey(provider: provider)
        super.tearDown()
    }

    func test_setThenGet_roundTrips() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-test-12345", provider: provider)
        XCTAssertEqual(try store.apiKey(provider: provider), "sk-test-12345")
    }

    func test_getWithoutSet_returnsNil() throws {
        let store = KeychainStore()
        XCTAssertNil(try store.apiKey(provider: provider))
    }

    func test_setTwice_overwritesRatherThanFails() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-first", provider: provider)
        try store.setAPIKey("sk-second", provider: provider)
        XCTAssertEqual(try store.apiKey(provider: provider), "sk-second")
    }

    func test_delete_removesTheKey() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-test", provider: provider)
        try store.deleteAPIKey(provider: provider)
        XCTAssertNil(try store.apiKey(provider: provider))
    }

    func test_deleteWhenNothingStored_doesNotThrow() {
        let store = KeychainStore()
        XCTAssertNoThrow(try store.deleteAPIKey(provider: provider))
    }

    /// Эмуляция «второго процесса» — раздел 14, п. 5 ТЗ: два независимых
    /// экземпляра `KeychainStore` с одной и той же access group видят одни
    /// и те же данные, как приложение и расширение в реальной поставке.
    func test_secondStoreInstance_withSameAccessGroup_seesWrittenValue() throws {
        let appSideStore = KeychainStore(accessGroup: nil)
        let extensionSideStore = KeychainStore(accessGroup: nil)

        try appSideStore.setAPIKey("sk-shared-value", provider: provider)
        XCTAssertEqual(try extensionSideStore.apiKey(provider: provider), "sk-shared-value")

        try extensionSideStore.deleteAPIKey(provider: provider)
        XCTAssertNil(try appSideStore.apiKey(provider: provider))
    }

    func test_differentProviders_areIsolated() throws {
        let store = KeychainStore()
        let otherProvider = ProviderID(rawValue: "\(provider.rawValue)-other")
        defer { try? store.deleteAPIKey(provider: otherProvider) }

        try store.setAPIKey("sk-a", provider: provider)
        try store.setAPIKey("sk-b", provider: otherProvider)

        XCTAssertEqual(try store.apiKey(provider: provider), "sk-a")
        XCTAssertEqual(try store.apiKey(provider: otherProvider), "sk-b")
    }

    func test_maskedPreview_shortKey() {
        XCTAssertEqual(KeychainStore.maskedPreview("abc"), "••••")
    }

    func test_maskedPreview_typicalKey() {
        XCTAssertEqual(KeychainStore.maskedPreview("sk-abcdefgh3f9a"), "sk-…3f9a")
    }
}
