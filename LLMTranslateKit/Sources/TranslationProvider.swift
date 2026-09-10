import Foundation

/// Раздел 6.1 ТЗ. Один протокол для всех провайдеров и обоих типов ввода
/// (текст/изображение) — не заводить параллельную ветку кода для картинок.
public protocol TranslationProvider: Sendable {
    var id: ProviderID { get }

    /// Потоковая выдача перевода. Возвращает дельты текста (не полный
    /// накопленный текст на каждой итерации).
    func translate(request: TranslationRequest) -> AsyncThrowingStream<String, Error>

    /// Проверка ключа и доступности модели — раздел 12, экран 2 ТЗ.
    func validate() async throws -> ProviderCapabilities

    /// Список моделей, если API его отдаёт. Раздел 6.4, п. 2 ТЗ: если запрос
    /// не удался — оставить свободный ввод строки (решение UI-слоя, не Kit).
    func listModels() async throws -> [ModelDescriptor]
}
