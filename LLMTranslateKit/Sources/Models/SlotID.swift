import Foundation

/// Идентификатор слота модели — раздел 5/11.2 ТЗ v1.2. Слот, не провайдер:
/// у `working` и `strong` может быть разный провайдер, разный ключ, разная
/// модель. Keychain и настройки адресуются по слоту, а не по `ProviderID`.
public struct SlotID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Рабочий слот — быстрый и дешёвый, используется всегда по умолчанию.
    public static let working = SlotID(rawValue: "working")
    /// Сильный слот — необязателен, включается кнопкой «Точнее».
    public static let strong = SlotID(rawValue: "strong")
}
