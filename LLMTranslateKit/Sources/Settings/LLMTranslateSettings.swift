import Foundation

/// Раздел 11.3 ТЗ v1.2.
public enum NotesMode: String, Sendable, Codable {
    /// Перевод без комментариев. Кнопка «Пояснить» доступна.
    case off
    /// Комментарии приходят сразу для коротких выделений, для длинных — по кнопке.
    case shortOnly
    /// Комментарии приходят всегда.
    case always
}

/// Раздел 5 ТЗ: несекретные настройки — в общем `UserDefaults(suiteName:)`
/// через App Group. Ключи ключей — в Keychain (`KeychainStore`), не здесь.
///
/// `UserDefaults` документирован Apple как потокобезопасный, поэтому
/// `@unchecked Sendable` — осознанное решение, а не обход проверки.
public final class LLMTranslateSettings: @unchecked Sendable {
    fileprivate let defaults: UserDefaults

    /// `nil`, если App Group ещё не сконфигурирована (например, в
    /// раннем юнит-тесте) — тогда используется locale-независимый дефолт
    /// в самом приложении, а не падение.
    public init?(appGroupSuiteName: String) {
        guard let defaults = UserDefaults(suiteName: appGroupSuiteName) else { return nil }
        self.defaults = defaults
    }

    /// Для юнит-тестов — изолированный `UserDefaults`, не App Group.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let primaryTargetLanguage = "primaryTargetLanguage"
        static let secondaryTargetLanguage = "secondaryTargetLanguage"
        static let notesMode = "notesMode"
        static let dictionaryModeEnabled = "dictionaryModeEnabled"
        static let customTextPrompt = "customTextPrompt"
        static let customImagePrompt = "customImagePrompt"
        static let customNotesAddendum = "customNotesAddendum"
        static let showOriginalTextInSheet = "showOriginalTextInSheet"
        static let cacheEnabled = "cacheEnabled"
        static let glossaryEntries = "glossaryEntries"
        static let textFirstByteTimeout = "textFirstByteTimeout"
        static let textTotalTimeout = "textTotalTimeout"
        static let imageFirstByteTimeout = "imageFirstByteTimeout"
        static let imageTotalTimeout = "imageTotalTimeout"
        static let textMaxOutputTokens = "textMaxOutputTokens"
        static let imageMaxOutputTokens = "imageMaxOutputTokens"
        static let connectionProfiles = "connectionProfiles"
        static let profilesMigrated = "profilesMigrated"
    }

    /// Раздел B5: коллекция профилей подключения. Ключи — в Keychain по `id`.
    public var connectionProfiles: [ConnectionProfile] {
        get {
            guard let data = defaults.data(forKey: Key.connectionProfiles) else { return [] }
            return (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.connectionProfiles)
        }
    }

    public func profile(id: UUID) -> ConnectionProfile? {
        connectionProfiles.first { $0.id == id }
    }

    /// Добавляет или обновляет профиль (по `id`).
    public func upsert(_ profile: ConnectionProfile) {
        var all = connectionProfiles
        if let index = all.firstIndex(where: { $0.id == profile.id }) {
            all[index] = profile
        } else {
            all.append(profile)
        }
        connectionProfiles = all
    }

    /// Удаляет профиль и его ключ; слоты, которые на него ссылались,
    /// становятся не настроенными (модель без подключения бессмысленна).
    public func removeProfile(id: UUID, keychain: KeychainStore) {
        try? keychain.deleteAPIKey(profile: id)
        connectionProfiles = connectionProfiles.filter { $0.id != id }
        for slotID in [SlotID.working, SlotID.strong] {
            let config = slot(slotID)
            if config.profileID == id {
                config.profileID = nil
                config.model = ""
                config.supportsImages = false
            }
        }
    }

    /// Подключение слота: через профиль, если слот на него ссылается, иначе
    /// прежние поля слота и ключ слота (так работают настройки до B5).
    public func connection(for slotID: SlotID, keychain: KeychainStore) -> ResolvedConnection {
        let config = slot(slotID)
        if let profileID = config.profileID, let profile = profile(id: profileID) {
            return ResolvedConnection(
                providerID: profile.providerID,
                baseURL: profile.baseURL,
                apiKey: (try? keychain.apiKey(profile: profileID)) ?? nil
            )
        }
        return ResolvedConnection(
            providerID: config.providerID,
            baseURL: config.baseURL,
            apiKey: (try? keychain.apiKey(slot: slotID)) ?? nil
        )
    }

    public var profilesMigrated: Bool {
        get { defaults.bool(forKey: Key.profilesMigrated) }
        set { defaults.set(newValue, forKey: Key.profilesMigrated) }
    }

    /// Раздел 7, п. 2 ТЗ: по умолчанию — язык интерфейса устройства.
    public var primaryTargetLanguage: Locale.Language {
        get {
            defaults.string(forKey: Key.primaryTargetLanguage).map { Locale.Language(identifier: $0) }
                ?? (Locale.current.language.languageCode.map { Locale.Language(languageCode: $0) }
                    ?? Locale.Language(identifier: "en"))
        }
        set { defaults.set(newValue.minimalIdentifier, forKey: Key.primaryTargetLanguage) }
    }

    public var secondaryTargetLanguage: Locale.Language {
        get {
            defaults.string(forKey: Key.secondaryTargetLanguage).map { Locale.Language(identifier: $0) }
                ?? Locale.Language(identifier: "en")
        }
        set { defaults.set(newValue.minimalIdentifier, forKey: Key.secondaryTargetLanguage) }
    }

    /// Раздел 11.3 ТЗ v1.2. По умолчанию `.off` — комментарии по запросу
    /// («Пояснить»), не навязчиво.
    public var notesMode: NotesMode {
        get {
            defaults.string(forKey: Key.notesMode).flatMap(NotesMode.init(rawValue:)) ?? .off
        }
        set { defaults.set(newValue.rawValue, forKey: Key.notesMode) }
    }

    /// Раздел 11.3 ТЗ v1.2: «Словарь для коротких выделений», по умолчанию включён.
    public var dictionaryModeEnabled: Bool {
        get { defaults.object(forKey: Key.dictionaryModeEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.dictionaryModeEnabled) }
    }

    /// Показывать ли исходный текст приглушённым текстом над переводом в
    /// шторке F1. По умолчанию выключено — пользователь и так знает, что
    /// выделил, повтор занимает место и не даёт сразу увидеть перевод.
    public var showOriginalTextInSheet: Bool {
        get { defaults.object(forKey: Key.showOriginalTextInSheet) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showOriginalTextInSheet) }
    }

    /// Раздел 11.4 ТЗ v1.2: «По умолчанию выключен» — осознанный размен
    /// приватности на скорость, включает пользователь сам.
    public var cacheEnabled: Bool {
        get { defaults.object(forKey: Key.cacheEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.cacheEnabled) }
    }

    /// Раздел 8.1/13.3 ТЗ v1.2. Пустой список по умолчанию — глоссарий не
    /// подставляется в промпт, пока пользователь не добавит хотя бы одну
    /// пару.
    public var glossaryEntries: [GlossaryEntry] {
        get {
            guard let data = defaults.data(forKey: Key.glossaryEntries) else { return [] }
            return (try? JSONDecoder().decode([GlossaryEntry].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.glossaryEntries)
        }
    }

    /// Раздел 13.5 ТЗ v1.2: настраиваемые таймауты и лимит вывода с экрана
    /// «Отладка и расход». Дефолты — те же значения, что раньше были
    /// захардкожены в `TranslationSession.run()`.
    public var textFirstByteTimeout: TimeInterval {
        get { defaults.object(forKey: Key.textFirstByteTimeout) as? TimeInterval ?? 8 }
        set { defaults.set(newValue, forKey: Key.textFirstByteTimeout) }
    }

    public var textTotalTimeout: TimeInterval {
        get { defaults.object(forKey: Key.textTotalTimeout) as? TimeInterval ?? 30 }
        set { defaults.set(newValue, forKey: Key.textTotalTimeout) }
    }

    public var imageFirstByteTimeout: TimeInterval {
        get { defaults.object(forKey: Key.imageFirstByteTimeout) as? TimeInterval ?? 20 }
        set { defaults.set(newValue, forKey: Key.imageFirstByteTimeout) }
    }

    public var imageTotalTimeout: TimeInterval {
        get { defaults.object(forKey: Key.imageTotalTimeout) as? TimeInterval ?? 60 }
        set { defaults.set(newValue, forKey: Key.imageTotalTimeout) }
    }

    public var textMaxOutputTokens: Int {
        get { defaults.object(forKey: Key.textMaxOutputTokens) as? Int ?? 2048 }
        set { defaults.set(newValue, forKey: Key.textMaxOutputTokens) }
    }

    public var imageMaxOutputTokens: Int {
        get { defaults.object(forKey: Key.imageMaxOutputTokens) as? Int ?? 4096 }
        set { defaults.set(newValue, forKey: Key.imageMaxOutputTokens) }
    }

    /// Раздел 8.1/12.3 ТЗ v1.2: редактируемые пользователем промпты. `nil` —
    /// используется дефолт из `PromptBuilder`, с кнопкой «сбросить к
    /// исходному» это ровно запись `nil` обратно.
    public var customTextPrompt: String? {
        get { defaults.string(forKey: Key.customTextPrompt) }
        set { defaults.set(newValue, forKey: Key.customTextPrompt) }
    }

    public var customImagePrompt: String? {
        get { defaults.string(forKey: Key.customImagePrompt) }
        set { defaults.set(newValue, forKey: Key.customImagePrompt) }
    }

    /// Раздел 8.3 ТЗ v1.2: надстройка для режима `.withNotes` — третий
    /// редактор промптов (12.3 ТЗ).
    public var customNotesAddendum: String? {
        get { defaults.string(forKey: Key.customNotesAddendum) }
        set { defaults.set(newValue, forKey: Key.customNotesAddendum) }
    }

    /// Раздел 5/11.2 ТЗ v1.2: два независимых слота, каждый — свой полный
    /// набор {провайдер, baseURL, модель, флаг мультимодальности}.
    public func slot(_ id: SlotID) -> ModelSlotConfig {
        ModelSlotConfig(defaults: defaults, slot: id)
    }
}

/// Настройки одного слота модели (`working`/`strong`). Хранится плоскими
/// ключами с префиксом слота в том же `UserDefaults`, что и остальные
/// несекретные настройки — не JSON-блобом, ради единообразия с остальным
/// файлом и простоты отладки через `defaults read`.
public struct ModelSlotConfig: @unchecked Sendable {
    fileprivate let defaults: UserDefaults
    public let slot: SlotID

    private enum Key {
        static let providerID = "providerID"
        static let baseURLString = "baseURLString"
        static let model = "model"
        static let supportsImages = "supportsImages"
        static let profileID = "profileID"
        static let disableReasoning = "disableReasoning"
    }

    /// Отключить «размышление» модели (только OpenRouter). По умолчанию
    /// выключено: не у всех моделей размышление можно отключить, поэтому
    /// включает его либо пользователь, либо мастер по данным рейтинга.
    public var disableReasoning: Bool {
        get { defaults.bool(forKey: key(Key.disableReasoning)) }
        nonmutating set { defaults.set(newValue, forKey: key(Key.disableReasoning)) }
    }

    /// Раздел B5: профиль, через который слот ходит в сеть. `nil` — слот
    /// настроен по-старому (собственные провайдер/адрес/ключ).
    public var profileID: UUID? {
        get { defaults.string(forKey: key(Key.profileID)).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: key(Key.profileID)) }
    }

    private func key(_ suffix: String) -> String { "\(slot.rawValue).\(suffix)" }

    public var providerID: ProviderID {
        get {
            defaults.string(forKey: key(Key.providerID)).map(ProviderID.init(rawValue:)) ?? .openAICompatible
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key(Key.providerID)) }
    }

    public var baseURL: URL {
        get {
            defaults.string(forKey: key(Key.baseURLString)).flatMap(URL.init(string:))
                ?? OpenAICompatibleProvider.defaultBaseURL
        }
        nonmutating set { defaults.set(newValue.absoluteString, forKey: key(Key.baseURLString)) }
    }

    public var model: String {
        get { defaults.string(forKey: key(Key.model)) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: key(Key.model)) }
    }

    /// Раздел 6.3 ТЗ: «В настройках слота — флаг «модель поддерживает
    /// изображения»». По умолчанию `false` — большинство текстовых моделей
    /// не мультимодальны, включать должен явно пользователь.
    public var supportsImages: Bool {
        get { defaults.bool(forKey: key(Key.supportsImages)) }
        nonmutating set { defaults.set(newValue, forKey: key(Key.supportsImages)) }
    }

    /// Раздел 11.2 ТЗ v1.2: «Если `strong` не настроен, кнопка [«Точнее»]
    /// скрыта». Модель — минимальный сигнал «слот заполнен»; ключ сам по
    /// себе живёт отдельно в Keychain и не проверяется здесь синхронно.
    public var isConfigured: Bool { !model.isEmpty }
}
