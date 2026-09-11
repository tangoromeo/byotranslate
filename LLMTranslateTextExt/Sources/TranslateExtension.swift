import SwiftUI
import TranslationUIProvider
import LLMTranslateKit

@main
final class TranslateExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslateSheetView(context: context)
        }
    }
}

// Этап 0, разбор Swift 6 strict concurrency вокруг TranslationUIProvider:
// `TranslationUIProviderContext` — protocol (не class), не Sendable, и SDK
// нигде не гарантирует, из какого actor-контекста framework вызывает
// content-замыкание `TranslationUIProviderSelectedTextScene.init(content:)`
// (сам init помечен `@MainActor`, а тип параметра-замыкания — нет).
// `nonisolated(unsafe)` — осознанный эскейп-хэтч: framework гарантирует
// однопоточное использование context в рамках одной шторки перевода,
// формальной Sendable-аннотации в SDK для этого протокола просто нет.
struct TranslateSheetView: View {
    nonisolated(unsafe) let context: any TranslationUIProviderContext

    @StateObject private var session: TranslationSession
    @State private var isShowingDetails = false
    @State private var isShowingNotes = false
    @State private var showOriginalText = false
    @State private var isLongText = false

    // Явный init, а не значение по умолчанию у @StateObject: дефолтное
    // значение сделало бы синтезированный memberwise init MainActor-
    // изолированным (TranslationSession — @MainActor), что ломает вызов
    // `TranslateSheetView(context:)` из незолированного замыкания SDK
    // (см. комментарий про Swift 6 strict concurrency выше).
    nonisolated init(context: any TranslationUIProviderContext) {
        self.context = context
        _session = StateObject(wrappedValue: TranslationSession(appGroupSuiteName: SharedIdentifiers.appGroup))
    }

    /// Раздел 9 ТЗ: «Длинный текст: шторка скроллится, автоматически
    /// вызывать expandSheet(), если исходный текст длиннее 200 символов».
    private static let expandThreshold = 200

    var body: some View {
        Group {
            if isLongText {
                // Раздел 9 ТЗ: для длинного текста уже вызван expandSheet()
                // — система сама даёт шторке полноэкранный контейнер, внутри
                // которого ScrollView занимает всё доступное место и
                // прижимает контент к верху. Ограничение по высоте здесь не
                // нужно (и вредно — оно центрировало ScrollView в большом
                // контейнере, оставляя пустоту сверху); оно нужно только в
                // ветке ниже, где expandSheet() не вызывается вовсе.
                ScrollView {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                content
            }
        }
        // Раздел 9 ТЗ: перевод стартует автоматически при появлении шторки.
        .task { await translate() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showOriginalText {
                Text(context.inputText ?? "")
                    .foregroundStyle(.secondary)
            }

            if let currentError = session.currentError {
                errorSection(currentError)
            } else {
                Text(session.translation)
                    .font(.body)
                if let usedSlot = session.usedSlot, usedSlot == .strong {
                    Text("Точнее — сильная модель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.isTranslating {
                    ProgressView()
                }
                if !session.notes.isEmpty {
                    DisclosureGroup("Пояснения (\(session.notes.count))", isExpanded: $isShowingNotes) {
                        ForEach(Array(session.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.caption)
                        }
                    }
                }
            }

            HStack {
                Button {
                    // Расхождение п. 4.5 ТЗ разрешено: SDK-интерфейс
                    // (arm64e-apple-ios.swiftinterface), справочник фреймворка
                    // TranslationUIProviderContext и штатный Xcode-темплейт
                    // "Translation Provider Extension" сходятся на
                    // `finish(translation:)`.
                    context.finish(translation: AttributedString(session.translation))
                } label: {
                    Text("Заменить")
                }
                .disabled(!context.allowsReplacement || session.translation.isEmpty)

                if session.canEscalate {
                    Button("Точнее") { Task { await session.escalateToStrong() } }
                }
                if session.canRequestNotes {
                    Button("Пояснить") { Task { await session.requestNotes() } }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Раздел 11 ТЗ: «Полный текст ошибки провайдера — в раскрывающейся
    /// секции «Подробности», для отладки».
    @ViewBuilder
    private func errorSection(_ error: TranslationError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.localizedUserMessage)
                .foregroundStyle(.red)
            if let details = error.details {
                DisclosureGroup("Подробности", isExpanded: $isShowingDetails) {
                    Text(details)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func translate() async {
        showOriginalText = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup)?.showOriginalTextInSheet ?? false

        guard let inputText = context.inputText, !inputText.characters.isEmpty else { return }
        let original = String(inputText.characters)
        if original.count > Self.expandThreshold {
            isLongText = true
            context.expandSheet()
        }
        await session.startText(original)
    }
}
