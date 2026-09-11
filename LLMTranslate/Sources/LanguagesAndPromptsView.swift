import SwiftUI
import LLMTranslateKit

/// Раздел 13, экран 3 ТЗ v1.2: `primaryTarget`/`secondaryTarget`, режим
/// комментариев, порог словарного режима, редакторы промптов, редактор
/// глоссария.
struct LanguagesAndPromptsView: View {
    let settings: LLMTranslateSettings?

    @State private var primaryTargetCode: String = "ru"
    @State private var secondaryTargetCode: String = "en"
    @State private var notesMode: NotesMode = .off
    @State private var dictionaryModeEnabled: Bool = true
    @State private var showOriginalText: Bool = false

    var body: some View {
        Form {
            Section("Языки") {
                TextField("Основной целевой (BCP-47, напр. ru)", text: $primaryTargetCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Вторичный целевой (BCP-47, напр. en)", text: $secondaryTargetCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Шторка перевода") {
                Toggle("Показывать исходный текст", isOn: $showOriginalText)
            }

            Section("Комментарии и словарь") {
                Picker("Комментарии модели", selection: $notesMode) {
                    Text("Не показывать").tag(NotesMode.off)
                    Text("Для коротких выделений").tag(NotesMode.shortOnly)
                    Text("Всегда").tag(NotesMode.always)
                }
                Toggle("Словарь для коротких выделений", isOn: $dictionaryModeEnabled)
            }

            Section("Промпты") {
                NavigationLink("Промпт для текста") {
                    PromptEditorView(
                        title: "Промпт для текста",
                        defaultText: PromptBuilder.defaultTextSystemPrompt,
                        get: { settings?.customTextPrompt },
                        set: { settings?.customTextPrompt = $0; clearCache() }
                    )
                }
                NavigationLink("Промпт для изображений") {
                    PromptEditorView(
                        title: "Промпт для изображений",
                        defaultText: PromptBuilder.defaultImageSystemPrompt,
                        get: { settings?.customImagePrompt },
                        set: { settings?.customImagePrompt = $0; clearCache() }
                    )
                }
                NavigationLink("Надстройка «Пояснить»") {
                    PromptEditorView(
                        title: "Надстройка «Пояснить»",
                        defaultText: PromptBuilder.defaultNotesAddendum,
                        get: { settings?.customNotesAddendum },
                        set: { settings?.customNotesAddendum = $0; clearCache() }
                    )
                }
                NavigationLink("Глоссарий") {
                    GlossaryEditorView(settings: settings)
                }
            }

            Section {
                Button("Сохранить") { save() }
            }
        }
        .navigationTitle("Языки и промпты")
        .onAppear(perform: load)
    }

    private func clearCache() {
        // Раздел 11.4 ТЗ: «Кэш полностью очищается при смене... системного
        // промпта».
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }

    private func load() {
        guard let settings else { return }
        primaryTargetCode = settings.primaryTargetLanguage.minimalIdentifier
        secondaryTargetCode = settings.secondaryTargetLanguage.minimalIdentifier
        notesMode = settings.notesMode
        dictionaryModeEnabled = settings.dictionaryModeEnabled
        showOriginalText = settings.showOriginalTextInSheet
    }

    private func save() {
        guard let settings else { return }
        settings.primaryTargetLanguage = Locale.Language(identifier: primaryTargetCode)
        settings.secondaryTargetLanguage = Locale.Language(identifier: secondaryTargetCode)
        settings.notesMode = notesMode
        settings.dictionaryModeEnabled = dictionaryModeEnabled
        settings.showOriginalTextInSheet = showOriginalText
    }
}
