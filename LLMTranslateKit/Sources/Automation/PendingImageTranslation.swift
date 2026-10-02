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

    /// Хендофф актуален только в момент запуска команды: холодный старт
    /// приложения из интента укладывается в секунды. Файл старше этого —
    /// остаток прошлого запуска, показывать его нельзя (иначе запуск с иконки
    /// открывал бы последний переведённый скриншот).
    nonisolated static let handoffMaxAge: TimeInterval = 30

    /// Читает файл и удаляет его в любом случае. `nil`, если файла нет или он
    /// просрочен.
    nonisolated static func takeFreshData(
        at url: URL,
        maxAge: TimeInterval = handoffMaxAge,
        now: Date = Date()
    ) -> Data? {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(modified) <= maxAge
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Вызывается приложением при выходе на передний план (раздел 10.4 ТЗ).
    /// Файлы хендоффа удаляются ВСЕГДА, даже если `perform()` уже показал
    /// результат напрямую в этом процессе (тогда файл лишний и иначе лежал бы
    /// до следующего запуска). Показывается только свежий хендофф и только
    /// если в этот момент ничего не показано.
    public func consumeHandoff(appGroupSuiteName: String) {
        let freshImage = Self.imageHandoffURL(appGroupSuiteName: appGroupSuiteName)
            .flatMap { Self.takeFreshData(at: $0) }
        let freshError = Self.errorHandoffURL(appGroupSuiteName: appGroupSuiteName)
            .flatMap { Self.takeFreshData(at: $0) }

        guard imageData == nil, error == nil else { return }

        if let freshImage {
            present(imageData: freshImage)
        } else if let freshError,
                  let payload = try? JSONSerialization.jsonObject(with: freshError) as? [String: String],
                  let tag = payload["tag"] {
            switch tag {
            case "noPhotoAccess": present(error: .noPhotoAccess)
            case "noScreenshotsFound": present(error: .noScreenshotsFound)
            default: present(error: .other(code: nil, message: payload["message"] ?? "неизвестная ошибка"))
            }
        }
    }

    /// Уход в фон: показанный результат больше не нужен, а просроченные файлы
    /// хендоффа не должны лежать на диске. Свежие не трогаем — холодный запуск
    /// из интента может увести сцену в фон до того, как они будут прочитаны.
    public func discardOnBackground(appGroupSuiteName: String) {
        clear()
        for url in [Self.imageHandoffURL(appGroupSuiteName: appGroupSuiteName),
                    Self.errorHandoffURL(appGroupSuiteName: appGroupSuiteName)].compactMap({ $0 }) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) > Self.handoffMaxAge
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
