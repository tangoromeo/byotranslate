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
