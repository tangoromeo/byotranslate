import Foundation

/// Раздел 10.4 ТЗ: мост между App Intent (`TranslateLatestScreenshotIntent`,
/// `TranslateImageIntent`) и UI хост-приложения.
///
/// **Почему не только in-memory синглтон.** Изначально предполагалось, что
/// App Intent с `openAppWhenRun = true`, объявленный в таргете приложения,
/// всегда выполняется в процессе самого приложения. На практике (проверено
/// живьём: команда «Сделать снимок экрана» → «Перевести изображение»,
/// назначенная на кнопку «Действие», при холодном запуске) `perform()`
/// может выполниться в отдельном, недолговечном процессе — установка
/// `@Published`-свойства там не долетает до `PendingImageTranslation.shared`
/// в процессе, где потом реально рисуется UI: это два разных экземпляра
/// синглтона в разных адресных пространствах. Поэтому `present(imageData:)`
/// остаётся (покрывает случай «приложение уже было открыто», без задержки на
/// чтение файла), но дополнительно данные передаются через App Group.
///
/// **Про раздел 10.7 ТЗ** («изображение не сохраняется на диск... в том
/// числе во временную директорию»): это требование к самому конвейеру
/// перевода (не держать оригинал/уменьшенную копию/base64 одновременно на
/// диске). Передача между процессами — отдельная задача, для которой в iOS
/// нет способа обойтись вовсе без диска; выбор в пользу временного файла,
/// который читается и немедленно удаляется в `consumeHandoff`, а не остаётся
/// лежать, сделан явно и по согласованию с пользователем, не по умолчанию.
@MainActor
public final class PendingImageTranslation: ObservableObject {
    public static let shared = PendingImageTranslation()

    @Published public private(set) var imageData: Data?
    @Published public private(set) var error: TranslationError?

    private init() {}

    public func present(imageData: Data) {
        error = nil
        self.imageData = imageData
    }

    /// Раздел 11 ТЗ: «Если скриншотов нет или доступ не выдан — понятная
    /// ошибка, а не тихий выход» — интент не может показать UI сам, поэтому
    /// кладёт ошибку сюда, приложение показывает её при выходе на передний план.
    public func present(error: TranslationError) {
        imageData = nil
        self.error = error
    }

    public func clear() {
        imageData = nil
        error = nil
    }

    // MARK: - Межпроцессная передача (App Group)

    private nonisolated static func imageHandoffURL(appGroupSuiteName: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent("pending-image-handoff.dat")
    }

    private nonisolated static func errorHandoffURL(appGroupSuiteName: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent("pending-error-handoff.json")
    }

    /// Вызывается из `perform()` App Intent'а сразу за `present(imageData:)`
    /// — на случай, если этот конкретный запуск окажется в отдельном процессе.
    public nonisolated static func handOff(imageData: Data, appGroupSuiteName: String) {
        guard let url = imageHandoffURL(appGroupSuiteName: appGroupSuiteName) else { return }
        try? FileManager.default.removeItem(at: url)
        try? imageData.write(to: url, options: .atomic)
    }

    public nonisolated static func handOff(error: TranslationError, appGroupSuiteName: String) {
        guard let url = errorHandoffURL(appGroupSuiteName: appGroupSuiteName) else { return }
        let tag: String
        var message: String?
        switch error {
        case .noPhotoAccess: tag = "noPhotoAccess"
        case .noScreenshotsFound: tag = "noScreenshotsFound"
        case let .other(_, msg): tag = "other"; message = msg
        default: tag = "other"; message = error.localizedUserMessage
        }
        let payload: [String: String] = message.map { ["tag": tag, "message": $0] } ?? ["tag": tag]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.removeItem(at: url)
        try? data.write(to: url, options: .atomic)
    }

    /// Вызывается приложением при выходе на передний план (раздел 10.4 ТЗ) —
    /// читает и сразу удаляет файл(ы), если есть. Идемпотентна: если
    /// `perform()` уже успел выполниться в этом же процессе и обновить
    /// `imageData`/`error` напрямую, повторно ничего не переписывает.
    public func consumeHandoff(appGroupSuiteName: String) {
        if imageData == nil, error == nil,
           let url = Self.imageHandoffURL(appGroupSuiteName: appGroupSuiteName),
           let data = try? Data(contentsOf: url) {
            try? FileManager.default.removeItem(at: url)
            present(imageData: data)
            return
        }
        if imageData == nil, error == nil,
           let url = Self.errorHandoffURL(appGroupSuiteName: appGroupSuiteName),
           let data = try? Data(contentsOf: url),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let tag = payload["tag"] {
            try? FileManager.default.removeItem(at: url)
            switch tag {
            case "noPhotoAccess": present(error: .noPhotoAccess)
            case "noScreenshotsFound": present(error: .noScreenshotsFound)
            default: present(error: .other(code: nil, message: payload["message"] ?? "неизвестная ошибка"))
            }
        }
    }
}
