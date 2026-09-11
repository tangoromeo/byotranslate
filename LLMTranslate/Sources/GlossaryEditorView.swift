import SwiftUI
import LLMTranslateKit

/// Раздел 8.1/13.3 ТЗ v1.2: построчный редактор глоссария (термин →
/// перевод), подставляемого в системный промпт. Явное «Сохранить», как и
/// весь остальной хост — не автосохранение по каждому нажатию.
struct GlossaryEditorView: View {
    let settings: LLMTranslateSettings?

    @State private var entries: [GlossaryEntry] = []
    @State private var newTerm = ""
    @State private var newTranslation = ""

    var body: some View {
        Form {
            Section {
                ForEach($entries) { $entry in
                    VStack(alignment: .leading) {
                        TextField("Термин", text: $entry.term)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Перевод", text: $entry.translation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { entries.remove(atOffsets: $0) }
            } header: {
                Text("Глоссарий")
            } footer: {
                Text("Обязательная терминология для перевода — например, названия продуктов или устоявшиеся переводы. Подставляется в системный промпт.")
            }

            Section("Добавить пару") {
                TextField("Термин", text: $newTerm)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Перевод", text: $newTranslation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Добавить") {
                    entries.append(GlossaryEntry(term: newTerm, translation: newTranslation))
                    newTerm = ""
                    newTranslation = ""
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section {
                Button("Сохранить") { save() }
            }
        }
        .navigationTitle("Глоссарий")
        .toolbar { EditButton() }
        .onAppear { entries = settings?.glossaryEntries ?? [] }
    }

    private func save() {
        settings?.glossaryEntries = entries
        // Раздел 11.4 ТЗ: смена глоссария меняет промпт — те же основания
        // для сброса кэша, что при смене слота/модели/системного промпта.
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }
}
