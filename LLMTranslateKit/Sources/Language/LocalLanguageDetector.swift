import Foundation
import NaturalLanguage

/// Раздел 7, п. 1 ТЗ: `NLLanguageRecognizer`, по первым 500 символам, топ-2
/// гипотезы с вероятностями. Тонкая обвязка над системным фреймворком —
/// логика ветвления по вероятности/длине текста живёт в
/// `LanguagePairResolver` и тестируется отдельно от неё.
public enum LocalLanguageDetector {
    private static let maxCharactersToAnalyze = 500

    public static func detectTopHypothesis(in text: String) -> (language: Locale.Language, confidence: Double)? {
        let sample = String(text.prefix(maxCharactersToAnalyze))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        return (Locale.Language(identifier: best.key.rawValue), best.value)
    }

    public static func resolvePair(
        for text: String,
        primaryTarget: Locale.Language,
        secondaryTarget: Locale.Language
    ) -> LanguagePairResolution {
        let hypothesis = detectTopHypothesis(in: text)
        return LanguagePairResolver.resolve(
            rawDetectedLanguage: hypothesis?.language,
            confidence: hypothesis?.confidence ?? 0,
            textLength: text.count,
            primaryTarget: primaryTarget,
            secondaryTarget: secondaryTarget
        )
    }
}
