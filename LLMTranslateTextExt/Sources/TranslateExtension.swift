import SwiftUI
import TranslationUIProvider
import LLMTranslateKit
import os.log

private let log = Logger(subsystem: "com.tyrex.llmtranslate", category: "text-translation")

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
    @State private var currentError: TranslationError?
    @State private var isShowingDetails = false

    private let keychain = KeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.inputText ?? "")
                .foregroundStyle(.secondary)

            if let currentError {
                Text(currentError.localizedUserMessage)
                    .foregroundStyle(.red)
                // Раздел 11 ТЗ: «Полный текст ошибки провайдера — в
                // раскрывающейся секции «Подробности», для отладки».
                if let details = currentError.details {
                    DisclosureGroup("Подробности", isExpanded: $isShowingDetails) {
                        Text(details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
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
            fail(.other(code: nil, message: "App Group не сконфигурирована"))
            return
        }
        guard let apiKey = (try? keychain.apiKey(provider: settings.providerID)) ?? nil, !apiKey.isEmpty else {
            fail(.missingAPIKey)
            return
        }
        guard !settings.model.isEmpty else {
            fail(.other(code: nil, message: "Модель не выбрана в настройках"))
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

        log.notice("translate start: baseURL=\(settings.baseURL.absoluteString, privacy: .public) model=\(settings.model, privacy: .public) textLength=\(original.count, privacy: .public)")
        isTranslating = true
        defer { isTranslating = false }

        var accumulated = ""
        do {
            let start = Date()
            var deltaCount = 0
            for try await delta in provider.translate(request: request) {
                if deltaCount == 0 {
                    log.notice("first delta after \(Date().timeIntervalSince(start), privacy: .public)s")
                }
                deltaCount += 1
                accumulated += delta
                translatedText = accumulated
            }
            log.notice("stream finished after \(Date().timeIntervalSince(start), privacy: .public)s, \(deltaCount, privacy: .public) deltas")
            translatedText = ResponseSanitizer.sanitize(accumulated, original: original)
        } catch let error as TranslationError {
            fail(error)
        } catch {
            fail(.other(code: nil, message: String(describing: error)))
        }
    }

    private func fail(_ error: TranslationError) {
        log.error("translate failed: \(String(describing: error), privacy: .public)")
        currentError = error
    }
}
