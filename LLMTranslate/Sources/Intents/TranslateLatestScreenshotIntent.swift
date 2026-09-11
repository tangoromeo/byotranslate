import AppIntents
import LLMTranslateKit

/// Раздел 10.4/10.9 ТЗ (E2/E3). `openAppWhenRun = true` — результат нужно
/// показывать, значит без переднего плана не обойтись. Объявлен в основном
/// таргете приложения (раздел 3 ТЗ: «App Intents объявляются в основном
/// таргете — расширению они не нужны»), но исходник также состоит в
/// таргете `LLMTranslateControl` (Target Membership на оба таргета) —
/// иначе кнопка Пункта управления не сможет на него сослаться.
struct TranslateLatestScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Перевести последний скриншот"
    static let description = IntentDescription(
        """
        Готова сразу — ничего собирать не нужно. Берёт последний снимок экрана из «Фото» \
        (уже сохранённый туда системой в момент, когда вы жмёте кнопки скриншота) и переводит его.
        """,
        categoryName: "Перевод"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let data = try await ScreenshotFetcher.fetchLatestScreenshotData()
            PendingImageTranslation.shared.present(imageData: data)
            // На случай, если этот конкретный запуск исполняется не в
            // процессе приложения — см. комментарий в PendingImageTranslation.
            PendingImageTranslation.handOff(imageData: data, appGroupSuiteName: SharedIdentifiers.appGroup)
        } catch let error as TranslationError {
            PendingImageTranslation.shared.present(error: error)
            PendingImageTranslation.handOff(error: error, appGroupSuiteName: SharedIdentifiers.appGroup)
        } catch {
            let wrapped = TranslationError.other(code: nil, message: String(describing: error))
            PendingImageTranslation.shared.present(error: wrapped)
            PendingImageTranslation.handOff(error: wrapped, appGroupSuiteName: SharedIdentifiers.appGroup)
        }
        return .result()
    }
}
