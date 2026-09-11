import XCTest
@testable import LLMTranslateKit

/// Раздел 11.4 ТЗ v1.2: ключ кэша детерминирован и различает все параметры,
/// от которых зависит результат перевода.
final class TranslationCacheKeyTests: XCTestCase {
    private func key(
        text: String = "Hello",
        source: String? = "en",
        target: String = "ru",
        slot: SlotID = .working,
        model: String = "gpt-5",
        prompt: String = "system prompt",
        mode: TranslationMode = .plain
    ) -> String {
        TranslationCacheKey.compute(
            normalizedText: text,
            sourceLanguageCode: source,
            targetLanguageCode: target,
            slot: slot,
            model: model,
            systemPrompt: prompt,
            mode: mode
        )
    }

    func test_sameInputs_produceSameKey() {
        XCTAssertEqual(key(), key())
    }

    func test_differentText_producesDifferentKey() {
        XCTAssertNotEqual(key(text: "Hello"), key(text: "Goodbye"))
    }

    func test_differentSourceLanguage_producesDifferentKey() {
        XCTAssertNotEqual(key(source: "en"), key(source: "fr"))
    }

    /// `compute` сворачивает `nil` в `""` внутри строки-конкатенации — это
    /// осознанное поведение (нет отдельного маркера "язык не определён"),
    /// не то, что стоит закреплять регрессионным тестом на несовпадение.
    func test_nilSourceLanguage_sameKeyAsEmptyString() {
        XCTAssertEqual(key(source: nil), key(source: ""))
    }

    func test_differentTargetLanguage_producesDifferentKey() {
        XCTAssertNotEqual(key(target: "ru"), key(target: "en"))
    }

    func test_differentSlot_producesDifferentKey() {
        XCTAssertNotEqual(key(slot: .working), key(slot: .strong))
    }

    func test_differentModel_producesDifferentKey() {
        XCTAssertNotEqual(key(model: "gpt-5"), key(model: "claude-5"))
    }

    func test_differentSystemPrompt_producesDifferentKey() {
        XCTAssertNotEqual(key(prompt: "a"), key(prompt: "b"))
    }

    func test_differentMode_producesDifferentKey() {
        XCTAssertNotEqual(key(mode: .plain), key(mode: .withNotes))
        XCTAssertNotEqual(key(mode: .withNotes), key(mode: .dictionary))
    }

    /// Разделитель полей (`\u{1F}`) не должен позволять двум разным
    /// разбиениям полей схлопнуться в один и тот же ключ.
    func test_fieldBoundaryConfusion_doesNotCollide() {
        let a = TranslationCacheKey.compute(
            normalizedText: "ab", sourceLanguageCode: "c", targetLanguageCode: "d",
            slot: .working, model: "m", systemPrompt: "p", mode: .plain
        )
        let b = TranslationCacheKey.compute(
            normalizedText: "a", sourceLanguageCode: "bc", targetLanguageCode: "d",
            slot: .working, model: "m", systemPrompt: "p", mode: .plain
        )
        XCTAssertNotEqual(a, b)
    }

    func test_normalize_trimsWhitespaceAndNewlines() {
        XCTAssertEqual(TranslationCacheKey.normalize("  Hello world  \n"), "Hello world")
    }

    func test_compute_returnsHexSHA256Length() {
        XCTAssertEqual(key().count, 64)
    }
}
