import Foundation

/// Раздел 5 ТЗ: несекретные настройки — в общем `UserDefaults(suiteName:)`
/// через App Group. Ключи ключей — в Keychain (`KeychainStore`), не здесь.
///
/// `UserDefaults` документирован Apple как потокобезопасный, поэтому
/// `@unchecked Sendable` — осознанное решение, а не обход проверки.
public final class LLMTranslateSettings: @unchecked Sendable {
    private let defaults: UserDefaults

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
        static let providerID = "providerID"
        static let baseURLString = "baseURLString"
        static let model = "model"
        static let primaryTargetLanguage = "primaryTargetLanguage"
        static let secondaryTargetLanguage = "secondaryTargetLanguage"
        static let supportsImages = "supportsImages"
    }

    public var providerID: ProviderID {
        get {
            defaults.string(forKey: Key.providerID).map(ProviderID.init(rawValue:)) ?? .openAICompatible
        }
        set { defaults.set(newValue.rawValue, forKey: Key.providerID) }
    }

    public var baseURL: URL {
        get {
            defaults.string(forKey: Key.baseURLString).flatMap(URL.init(string:))
                ?? OpenAICompatibleProvider.defaultBaseURL
        }
        set { defaults.set(newValue.absoluteString, forKey: Key.baseURLString) }
    }

    public var model: String {
        get { defaults.string(forKey: Key.model) ?? "" }
        set { defaults.set(newValue, forKey: Key.model) }
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

    /// Раздел 6.3 ТЗ: «В настройках провайдера — флаг «модель поддерживает
    /// изображения»». По умолчанию `false` — большинство текстовых моделей
    /// не мультимодальны, включать должен явно пользователь.
    public var supportsImages: Bool {
        get { defaults.bool(forKey: Key.supportsImages) }
        set { defaults.set(newValue, forKey: Key.supportsImages) }
    }
}
