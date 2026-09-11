import AppIntents

/// Раздел 10.9 ТЗ: «команды в поставке» — `AppShortcutsProvider` появляется в
/// приложении «Команды» сразу после установки, без действий пользователя.
/// Фраза обязана содержать `\(.applicationName)` — иначе не регистрируется.
/// Лимит — 10 App Shortcuts на приложение (проверено по HIG на этапе 0,
/// см. NOTES.md, п. 4) — здесь их два, далеко от лимита.
struct TranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateLatestScreenshotIntent(),
            phrases: [
                "Переведи скриншот в \(.applicationName)",
                "Translate screenshot with \(.applicationName)",
            ],
            shortTitle: "Перевести скриншот",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: TranslateImageIntent(),
            phrases: [
                "Переведи картинку в \(.applicationName)",
                "Translate image with \(.applicationName)",
            ],
            shortTitle: "Перевести изображение",
            systemImageName: "photo"
        )
    }
}
