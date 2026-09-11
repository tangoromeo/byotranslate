import XCTest
@testable import LLMTranslateKit

/// Раздел 14, п. 8 ТЗ v1.2: запись, чтение «из второго процесса», удаление,
/// независимость слотов.
///
/// По-настоящему протестировать два процесса юнит-тест не может — здесь и
/// приложение, и расширение эмулируются двумя независимыми
/// `KeychainStore` в одном тестовом раннере. Это проверяет контракт («один
/// и тот же access group ⇒ общие данные, разные ⇒ изолированные данные»),
/// а не реальную межпроцессную IPC-доставку — та проверяется только на
/// реальном устройстве/симуляторе с приложением и расширением, поставленными
/// из одного архива (см. критерии приёмки, раздел 16 ТЗ).
final class KeychainStoreTests: XCTestCase {
    private let slot = SlotID(rawValue: "test-slot-\(UUID().uuidString)")

    override func tearDown() {
        try? KeychainStore().deleteAPIKey(slot: slot)
        super.tearDown()
    }

    func test_setThenGet_roundTrips() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-test-12345", slot: slot)
        XCTAssertEqual(try store.apiKey(slot: slot), "sk-test-12345")
    }

    func test_getWithoutSet_returnsNil() throws {
        let store = KeychainStore()
        XCTAssertNil(try store.apiKey(slot: slot))
    }

    func test_setTwice_overwritesRatherThanFails() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-first", slot: slot)
        try store.setAPIKey("sk-second", slot: slot)
        XCTAssertEqual(try store.apiKey(slot: slot), "sk-second")
    }

    func test_delete_removesTheKey() throws {
        let store = KeychainStore()
        try store.setAPIKey("sk-test", slot: slot)
        try store.deleteAPIKey(slot: slot)
        XCTAssertNil(try store.apiKey(slot: slot))
    }

    func test_deleteWhenNothingStored_doesNotThrow() {
        let store = KeychainStore()
        XCTAssertNoThrow(try store.deleteAPIKey(slot: slot))
    }

    /// Эмуляция «второго процесса» — раздел 14, п. 8 ТЗ: два независимых
    /// экземпляра `KeychainStore` с одной и той же access group видят одни
    /// и те же данные, как приложение и расширение в реальной поставке.
    func test_secondStoreInstance_withSameAccessGroup_seesWrittenValue() throws {
        let appSideStore = KeychainStore(accessGroup: nil)
        let extensionSideStore = KeychainStore(accessGroup: nil)

        try appSideStore.setAPIKey("sk-shared-value", slot: slot)
        XCTAssertEqual(try extensionSideStore.apiKey(slot: slot), "sk-shared-value")

        try extensionSideStore.deleteAPIKey(slot: slot)
        XCTAssertNil(try appSideStore.apiKey(slot: slot))
    }

    /// Раздел 5 ТЗ v1.2: у `working` и `strong` независимые ключи, даже если
    /// оба указывают на одного и того же провайдера.
    func test_differentSlots_areIsolated() throws {
        let store = KeychainStore()
        let otherSlot = SlotID(rawValue: "\(slot.rawValue)-other")
        defer { try? store.deleteAPIKey(slot: otherSlot) }

        try store.setAPIKey("sk-a", slot: slot)
        try store.setAPIKey("sk-b", slot: otherSlot)

        XCTAssertEqual(try store.apiKey(slot: slot), "sk-a")
        XCTAssertEqual(try store.apiKey(slot: otherSlot), "sk-b")
    }

    func test_maskedPreview_shortKey() {
        XCTAssertEqual(KeychainStore.maskedPreview("abc"), "••••")
    }

    func test_maskedPreview_typicalKey() {
        XCTAssertEqual(KeychainStore.maskedPreview("sk-abcdefgh3f9a"), "sk-…3f9a")
    }
}
