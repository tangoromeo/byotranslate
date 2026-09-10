import XCTest
@testable import LLMTranslateKit

final class LanguagePairResolverTests: XCTestCase {
    private let ru = Locale.Language(identifier: "ru")
    private let en = Locale.Language(identifier: "en")
    private let he = Locale.Language(identifier: "he")

    /// Раздел 7, п. 3 ТЗ: определённый язык не равен primaryTarget → переводим в primaryTarget.
    func test_detectedDiffersFromPrimary_translatesToPrimary() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.9, textLength: 35,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertEqual(result.detectedSourceLanguage, he)
        XCTAssertEqual(result.targetLanguage, ru)
    }

    /// Раздел 7, п. 4 ТЗ: определённый язык равен primaryTarget → переводим в secondaryTarget.
    func test_detectedEqualsPrimary_translatesToSecondary() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: ru, confidence: 0.9, textLength: 35,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertEqual(result.detectedSourceLanguage, ru)
        XCTAssertEqual(result.targetLanguage, en)
    }

    func test_detectedEqualsPrimary_ignoringRegionVariant() {
        let americanEnglish = Locale.Language(identifier: "en-US")
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: americanEnglish, confidence: 0.9, textLength: 35,
            primaryTarget: en, secondaryTarget: ru
        )
        XCTAssertEqual(result.targetLanguage, ru)
    }

    /// Раздел 7, п. 5 ТЗ: уверенность ниже 0.5 → источник не передаём.
    func test_lowConfidence_dropsDetectedLanguage() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.49, textLength: 35,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertNil(result.detectedSourceLanguage)
        XCTAssertEqual(result.targetLanguage, ru)
    }

    func test_confidenceExactlyAtThreshold_isTrusted() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.5, textLength: 35,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertEqual(result.detectedSourceLanguage, he)
    }

    /// Порог поднят до 30 символов — см. комментарий у
    /// `LanguagePairResolver.minimumTextLength`: короче Apple прямо
    /// называет распознавание ненадёжным, независимо от того, что
    /// раздел 7, п. 5 ТЗ называет 3 символа.
    func test_tooShortText_dropsDetectedLanguage() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.9, textLength: 29,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertNil(result.detectedSourceLanguage)
        XCTAssertEqual(result.targetLanguage, ru)
    }

    /// Одно слово — типичный случай, из-за которого порог и подняли:
    /// проходит наивную длину, но недостаточно контекста для надёжного
    /// определения языка.
    func test_singleWordSelection_isTooShortToTrust() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.9, textLength: "Lepidoptera".count,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertNil(result.detectedSourceLanguage)
    }

    func test_textLengthExactlyAtThreshold_isTrusted() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: he, confidence: 0.9, textLength: 30,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertEqual(result.detectedSourceLanguage, he)
    }

    func test_noRawDetectedLanguage_fallsBackToPrimary() {
        let result = LanguagePairResolver.resolve(
            rawDetectedLanguage: nil, confidence: 0, textLength: 35,
            primaryTarget: ru, secondaryTarget: en
        )
        XCTAssertNil(result.detectedSourceLanguage)
        XCTAssertEqual(result.targetLanguage, ru)
    }
}
