import Foundation

public struct LanguagePairResolution: Sendable, Equatable {
    /// `nil`, если язык источника не передаём модели (раздел 7, п. 5 ТЗ) —
    /// в промпте в этом случае пишем «определи язык сам».
    public let detectedSourceLanguage: Locale.Language?
    public let targetLanguage: Locale.Language

    public init(detectedSourceLanguage: Locale.Language?, targetLanguage: Locale.Language) {
        self.detectedSourceLanguage = detectedSourceLanguage
        self.targetLanguage = targetLanguage
    }
}

/// Раздел 7 ТЗ, шесть ветвей алгоритма. Чистая функция — не зависит от
/// `NLLanguageRecognizer` напрямую, чтобы быть тестируемой без реального
/// распознавания текста (см. `LocalLanguageDetector` для интеграции с ним).
public enum LanguagePairResolver {
    /// Порог уверенности распознавания — п. 5 раздела 7 ТЗ.
    public static let minimumConfidence: Double = 0.5
    /// Минимальная длина текста, при которой распознаванию можно доверять —
    /// п. 5 раздела 7 ТЗ.
    public static let minimumTextLength = 3

    public static func resolve(
        rawDetectedLanguage: Locale.Language?,
        confidence: Double,
        textLength: Int,
        primaryTarget: Locale.Language,
        secondaryTarget: Locale.Language
    ) -> LanguagePairResolution {
        // п. 5: низкая уверенность или слишком короткий текст — не доверяем распознаванию.
        guard
            textLength >= minimumTextLength,
            confidence >= minimumConfidence,
            let detected = rawDetectedLanguage
        else {
            return LanguagePairResolution(detectedSourceLanguage: nil, targetLanguage: primaryTarget)
        }

        // п. 3/4: сравниваем по языковому коду (en vs en-GB — тот же язык).
        if detected.languageCode == primaryTarget.languageCode {
            return LanguagePairResolution(detectedSourceLanguage: detected, targetLanguage: secondaryTarget)
        } else {
            return LanguagePairResolution(detectedSourceLanguage: detected, targetLanguage: primaryTarget)
        }
    }
}
