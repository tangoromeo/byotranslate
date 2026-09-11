import Foundation
import CryptoKit

/// Раздел 11.4 ТЗ v1.2: «Ключ: SHA-256 от конкатенации нормализованного
/// исходного текста, кода языка источника, кода целевого языка,
/// идентификатора слота, имени модели, хэша системного промпта, значения
/// режима». Чистая функция — тестируема без Keychain/файлов.
public enum TranslationCacheKey {
    public static func compute(
        normalizedText: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String,
        slot: SlotID,
        model: String,
        systemPrompt: String,
        mode: TranslationMode
    ) -> String {
        let modeTag: String
        switch mode {
        case .plain: modeTag = "plain"
        case .withNotes: modeTag = "withNotes"
        case .dictionary: modeTag = "dictionary"
        }
        let systemPromptHash = sha256Hex(systemPrompt)
        let combined = [
            normalizedText,
            sourceLanguageCode ?? "",
            targetLanguageCode,
            slot.rawValue,
            model,
            systemPromptHash,
            modeTag,
        ].joined(separator: "\u{1F}") // unit separator — исключает коллизии от конкатенации без разделителя
        return sha256Hex(combined)
    }

    /// Раздел 11.4 ТЗ подразумевает «нормализованный» текст — тримминг
    /// краевых пробелов, чтобы «Hello» и « Hello » не считались разными
    /// ключами кэша (сам перевод при этом не меняется, это только про ключ).
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
