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

    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?

    private let keychain = KeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.inputText ?? "")
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text(translatedText)
                    .font(.headline)
                if isTranslating {
                    ProgressView()
                }
            }

            Button {
                // Расхождение п. 4.5 ТЗ разрешено: SDK-интерфейс
                // (arm64e-apple-ios.swiftinterface), справочник фреймворка
                // TranslationUIProviderContext и штатный Xcode-темплейт
                // "Translation Provider Extension" сходятся на
                // `finish(translation:)`.
                context.finish(translation: AttributedString(translatedText))
            } label: {
                Text("Заменить")
            }
            .disabled(!context.allowsReplacement || translatedText.isEmpty)
        }
        .padding(8)
        // Раздел 9 ТЗ: перевод стартует автоматически при появлении шторки.
        .task { await translate() }
    }

    private func translate() async {
        guard let inputText = context.inputText, !inputText.characters.isEmpty else { return }
        let original = String(inputText.characters)

        guard let settings = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup) else {
            errorMessage = "App Group не сконфигурирована"
            return
        }
        guard let apiKey = (try? keychain.apiKey(provider: settings.providerID)) ?? nil, !apiKey.isEmpty else {
            errorMessage = TranslationError.missingAPIKey.localizedUserMessage
            return
        }
        guard !settings.model.isEmpty else {
            errorMessage = "Модель не выбрана в настройках"
            return
        }

        let pair = LocalLanguageDetector.resolvePair(
            for: original,
            primaryTarget: settings.primaryTargetLanguage,
            secondaryTarget: settings.secondaryTargetLanguage
        )
        let systemPrompt = PromptBuilder.render(
            template: PromptBuilder.defaultTextSystemPrompt,
            targetLanguage: pair.targetLanguage,
            glossary: [:]
        )
        let request = TranslationRequest(
            payload: .text(original),
            detectedSourceLanguage: pair.detectedSourceLanguage,
            targetLanguage: pair.targetLanguage,
            systemPrompt: systemPrompt
        )
        let provider = OpenAICompatibleProvider(baseURL: settings.baseURL, apiKey: apiKey, model: settings.model)

        isTranslating = true
        defer { isTranslating = false }

        var accumulated = ""
        do {
            for try await delta in provider.translate(request: request) {
                accumulated += delta
                translatedText = accumulated
            }
            translatedText = ResponseSanitizer.sanitize(accumulated, original: original)
        } catch let error as TranslationError {
            errorMessage = error.localizedUserMessage
        } catch {
            errorMessage = TranslationError.other(code: nil, message: String(describing: error)).localizedUserMessage
        }
    }
}
