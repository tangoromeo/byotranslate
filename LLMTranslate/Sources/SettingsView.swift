import SwiftUI
import LLMTranslateKit

/// Раздел 13 ТЗ v1.2: хост-приложение — пять минимальных экранов. Этот файл
/// — точка входа (домашнее меню) плюс общие подэкраны слотов/промптов,
/// переиспользуемые из `LanguagesAndPromptsView`.
struct SettingsView: View {
    private let settings = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup)

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Как начать") {
                    OnboardingView()
                }
                NavigationLink("Модели") {
                    ModelsHomeView(settings: settings)
                }
                NavigationLink("Языки и промпты") {
                    LanguagesAndPromptsView(settings: settings)
                }
                NavigationLink("Отладка и расход") {
                    DebugAndUsageView(settings: settings)
                }
            }
            .navigationTitle("BYO Translate")
        }
        // Раздел B5: слоты, настроенные до профилей, становятся профилями
        // (идемпотентно); сеть работает и без этого — см. `connection(for:)`.
        .task {
            if let settings {
                ProfileMigration.run(settings: settings, keys: .keychain(KeychainStore()))
            }
        }
    }
}

/// Раздел 8.1/8.3/12.3 ТЗ v1.2: редактор одного промпта с кнопкой «сбросить
/// к исходному». `nil` в настройках — используется дефолт из `PromptBuilder`.
/// Не `private` — переиспользуется из `LanguagesAndPromptsView`.
struct PromptEditorView: View {
    let title: String
    let defaultText: String
    let get: () -> String?
    let set: (String?) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(4)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Готово") {
                    set(text == defaultText ? nil : text)
                    dismiss()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Сбросить к исходному") { text = defaultText }
            }
        }
        .onAppear { text = get() ?? defaultText }
    }
}

#Preview {
    SettingsView()
}
