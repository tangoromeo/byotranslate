import Foundation

/// Кэш переводов фрагментов скриншота («Весь экран», «Перевести на месте»).
/// Ключ — маска надписи (`CropFingerprint`) плюс всё, от чего зависит перевод:
/// целевой язык, провайдер и модель рабочего слота, промпт листов и глоссарий.
/// Совпадение — точное или «почти та же маска» с узким допуском: шум фона
/// проходит, а замена одной цифры («Счёт …1234» / «…1235») — нет; ложное
/// попадание дало бы чужой перевод, промах — всего лишь лишний запрос.
///
/// Отход от раздела 11.4 ТЗ («изображения не кэшируются»): хранятся не
/// изображения, а хеш надписи и текст перевода, в том же зашифрованном кэше и
/// только при включённом переключателе «Кэшировать переводы».
struct RegionTranslationCache {
    private let cache: TranslationCache
    private let target: String
    private let modelIdentity: String
    private let prompt: String

    init?(appGroupSuiteName: String) {
        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName), settings.cacheEnabled else { return nil }
        let slot = settings.slot(.working)
        guard !slot.model.isEmpty else { return nil }
        let connection = settings.connection(for: .working, keychain: KeychainStore())
        cache = TranslationCache(appGroupSuiteName: appGroupSuiteName)
        target = settings.primaryTargetLanguage.minimalIdentifier
        modelIdentity = "\(connection.providerID.rawValue)|\(connection.baseURL.absoluteString)|\(slot.model)"
        let glossary = GlossaryEntry.asDictionary(settings.glossaryEntries)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        prompt = PromptBuilder.defaultRegionsSystemPrompt + "\n" + glossary
    }

    /// Контекст, в котором перевод действителен: язык, провайдер и модель, промпт с глоссарием.
    private var context: String {
        TranslationCacheKey.compute(
            normalizedText: "region-context", sourceLanguageCode: nil, targetLanguageCode: target,
            slot: .working, model: modelIdentity, systemPrompt: prompt, mode: .plain
        )
    }

    func query(for signature: CropFingerprint.Signature) -> RegionCacheQuery {
        let key = TranslationCacheKey.compute(
            normalizedText: "region-mask:" + signature.key,
            sourceLanguageCode: nil,
            targetLanguageCode: target,
            slot: .working,
            model: modelIdentity,
            systemPrompt: prompt,
            mode: .plain
        )
        return RegionCacheQuery(key: key, signature: signature)
    }

    /// Ключ сигнатуры → перевод для найденных (точно или «почти та же надпись»).
    func lookup(_ signatures: [CropFingerprint.Signature]) -> [String: String] {
        let queries = signatures.map(query(for:))
        let found = cache.regionTranslations(for: queries, context: context)
        var result: [String: String] = [:]
        for (signature, query) in zip(signatures, queries) {
            if let text = found[query.key] { result[signature.key] = text }
        }
        return result
    }

    func store(_ items: [(signature: CropFingerprint.Signature, translation: String)]) {
        cache.setRegionTranslations(items.map { (query(for: $0.signature), $0.translation) }, context: context)
    }
}
