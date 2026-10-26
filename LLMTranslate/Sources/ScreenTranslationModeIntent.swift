import AppIntents
import LLMTranslateKit

/// Возвращает настройку «как показывать перевод экрана», чтобы команда
/// «Перевести экран» ветвилась через «Если»: само действие не может на лету
/// решить, открывать приложение или нет (`openAppWhenRun` статичен).
/// `true` — открыть BYO Translate («Перевести изображение»), `false` — на месте
/// («Перевести на месте» → «Быстрый просмотр»).
struct ScreenTranslationModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Режим перевода экрана"
    static let description = IntentDescription(
        "Возвращает «Да», если в настройках BYO Translate выбран показ перевода в приложении, и «Нет», если на месте.",
        categoryName: "Перевод"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let opensApp = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup)?.screenTranslationOpensApp ?? false
        return .result(value: opensApp)
    }
}
