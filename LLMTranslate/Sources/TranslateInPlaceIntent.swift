import AppIntents
import LLMTranslateKit
import UniformTypeIdentifiers

/// «Перевести на месте»: в отличие от `TranslateImageIntent` не открывает
/// приложение. Переводит снимок плашками поверх оригинала и возвращает картинку
/// в команду; следующий шаг «Быстрый просмотр» показывает её поверх текущего
/// приложения, и после закрытия пользователь остаётся там же (проверено вживую).
/// Рецепт: «Сделать снимок экрана» → «Перевести на месте» → «Быстрый просмотр»,
/// на кнопку «Действие» или касание AssistiveTouch / задней панели.
///
/// Лежит вне `Intents/`: ту папку компилирует и таргет кнопки Пункта управления,
/// а ему это действие не нужно.
struct TranslateInPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Перевести на месте"
    static let description = IntentDescription(
        """
        Переводит текст на изображении плашками поверх оригинала и возвращает картинку, не открывая приложение. \
        Рецепт: «Сделать снимок экрана» → «Перевести на месте» → «Быстрый просмотр».
        """,
        categoryName: "Перевод"
    )
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Перевести на месте \(\.$image)")
    }

    // Как у TranslateImageIntent: без `connectToPreviousIntentResult` «Команды»
    // не подставляют вывод предыдущего шага.
    @Parameter(
        title: "Изображение",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data: Data
        do {
            data = try image.data
        } catch {
            throw InPlaceIntentError.message("Не удалось прочитать изображение")
        }
        do {
            let output = try await InPlaceTranslation.translate(imageData: data, appGroupSuiteName: SharedIdentifiers.appGroup)
            return .result(value: IntentFile(data: output.imageData, filename: "BYO Translate.jpg", type: .jpeg))
        } catch let failure as InPlaceTranslation.Failure {
            switch failure {
            case .unreadableImage: throw InPlaceIntentError.message("Не удалось прочитать изображение")
            case .noTextFound: throw InPlaceIntentError.message("На снимке не найден текст")
            case .nothingTranslated: throw InPlaceIntentError.message("Модель не вернула перевод")
            case let .translation(error): throw InPlaceIntentError.message(error.localizedUserMessage)
            }
        }
    }
}

/// Текст ошибки, который «Команды» покажут пользователю.
enum InPlaceIntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .message(text): LocalizedStringResource(stringLiteral: text)
        }
    }
}
