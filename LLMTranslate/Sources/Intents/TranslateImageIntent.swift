import AppIntents
import LLMTranslateKit
import UniformTypeIdentifiers

/// Раздел 10.4 ТЗ: принимает изображение из любой пользовательской команды
/// («Команды»), не только из «Фото» — даёт пользователю собрать собственные
/// сценарии (например, из скриншота, снятого другим шорткатом, или из файла).
/// В отличие от `TranslateLatestScreenshotIntent` сам по себе не
/// устанавливается «из коробки» как самодостаточное действие — это
/// строительный блок для цепочки (см. `description`), пользователь
/// собирает её сам в «Командах» ровно один раз.
struct TranslateImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Перевести изображение (из другого действия)"
    static let description = IntentDescription(
        """
        Переводит изображение, переданное из предыдущего шага команды — само по себе не запускается. \
        Рецепт для кнопки «Действие» без сохранения в «Фото»: «Сделать снимок экрана» → «Перевести изображение».
        """,
        categoryName: "Перевод"
    )
    static let openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Перевести изображение \(\.$image)")
    }

    // `supportedContentTypes` одного не хватает — Shortcuts всё равно
    // предлагает только выбор из библиотеки «Фото», не «Результат
    // предыдущего действия» (обнаружено вживую). Нужен ещё
    // `inputConnectionBehavior: .connectToPreviousIntentResult` — именно
    // он включает автоподстановку вывода предыдущего шага.
    @Parameter(
        title: "Изображение",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let data = try image.data
            PendingImageTranslation.shared.present(imageData: data)
            // На случай, если этот конкретный запуск исполняется не в
            // процессе приложения — см. комментарий в PendingImageTranslation.
            PendingImageTranslation.handOff(imageData: data, appGroupSuiteName: SharedIdentifiers.appGroup)
        } catch {
            let wrapped = TranslationError.other(code: nil, message: "не удалось прочитать переданное изображение")
            PendingImageTranslation.shared.present(error: wrapped)
            PendingImageTranslation.handOff(error: wrapped, appGroupSuiteName: SharedIdentifiers.appGroup)
        }
        return .result()
    }
}
