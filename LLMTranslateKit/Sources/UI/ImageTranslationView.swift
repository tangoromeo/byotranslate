#if canImport(UIKit)
import SwiftUI
import UIKit
import os.log

private let log = Logger(subsystem: "com.tyrex.llmtranslate", category: "image-translation")

/// Раздел 10.3/10.8 ТЗ: «Тот же UI результата, что и в остальных точках
/// входа — общий SwiftUI-компонент из LLMTranslateKit». Используется из
/// `LLMTranslateShareExt` сейчас, из App Intents/Control — на этапе 4.
///
/// Полноэкранный результат: миниатюра исходника сверху (тап — просмотр
/// оригинала), перевод потоком, «Копировать»/«Поделиться»/«Ещё раз».
/// Кнопки «Заменить» нет — заменять нечего (раздел 10.8 ТЗ).
public struct ImageTranslationView: View {
    private let originalImageData: Data
    private let appGroupSuiteName: String

    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var currentError: TranslationError?
    @State private var isShowingOriginal = false
    @State private var isShowingDetails = false
    @State private var copiedFeedback = false
    /// Инкрементируется, чтобы `.task(id:)` перезапустил перевод — так
    /// реализовано «Ещё раз».
    @State private var attempt = 0

    public init(originalImageData: Data, appGroupSuiteName: String) {
        self.originalImageData = originalImageData
        self.appGroupSuiteName = appGroupSuiteName
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                thumbnail

                if let currentError {
                    errorSection(currentError)
                } else {
                    Text(translatedText.isEmpty ? " " : translatedText)
                        .font(.body)
                        .textSelection(.enabled)
                    if isTranslating {
                        ProgressView()
                    }
                }

                buttonRow
            }
            .padding()
        }
        .sheet(isPresented: $isShowingOriginal) {
            originalImageSheet
        }
        .task(id: attempt) { await translate() }
    }

    /// Раздел 11 ТЗ: «Полный текст ошибки провайдера — в раскрывающейся
    /// секции «Подробности», для отладки» — до этого была только
    /// `localizedUserMessage`, реальная причина нигде не показывалась.
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

    private var thumbnail: some View {
        Group {
            if let uiImage = UIImage(data: originalImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { isShowingOriginal = true }
            }
        }
    }

    private var originalImageSheet: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let uiImage = UIImage(data: originalImageData) {
                    Image(uiImage: uiImage)
                }
            }
            .navigationTitle("Оригинал")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { isShowingOriginal = false }
                }
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = translatedText
                copiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
            } label: {
                Label(copiedFeedback ? "Скопировано" : "Копировать", systemImage: "doc.on.doc")
            }
            .disabled(translatedText.isEmpty)

            if !translatedText.isEmpty {
                ShareLink(item: translatedText) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                translatedText = ""
                currentError = nil
                attempt += 1
            } label: {
                Label("Ещё раз", systemImage: "arrow.clockwise")
            }
            .disabled(isTranslating)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
    }

    private func translate() async {
        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName) else {
            fail(.other(code: nil, message: "App Group не сконфигурирована"))
            return
        }
        guard settings.supportsImages else {
            // Раздел 10.6 ТЗ: при выключенном флаге — понятная ошибка, не
            // попытка вызвать API вслепую.
            fail(.modelDoesNotSupportImages)
            return
        }
        let keychain = KeychainStore()
        guard let apiKey = (try? keychain.apiKey(provider: settings.providerID)) ?? nil, !apiKey.isEmpty else {
            fail(.missingAPIKey)
            return
        }
        guard !settings.model.isEmpty else {
            fail(.other(code: nil, message: "Модель не выбрана в настройках"))
            return
        }

        log.notice("translate start: baseURL=\(settings.baseURL.absoluteString, privacy: .public) model=\(settings.model, privacy: .public) imageBytes=\(originalImageData.count, privacy: .public)")
        isTranslating = true
        defer { isTranslating = false }

        do {
            // Раздел 10.7 ТЗ: подготовка (даунскейл/кодирование/лимит payload).
            let prepared = try ImagePreparation.prepare(sourceData: originalImageData)
            log.notice("prepared image: \(prepared.data.count, privacy: .public) bytes, \(prepared.mimeType, privacy: .public)")

            // Раздел 10.6 ТЗ: для изображений локальное определение языка
            // не выполняется — язык определяет модель, всегда primaryTarget.
            let systemPrompt = PromptBuilder.render(
                template: PromptBuilder.defaultImageSystemPrompt,
                targetLanguage: settings.primaryTargetLanguage,
                glossary: [:]
            )
            let request = TranslationRequest(
                payload: .image(prepared.data, mime: prepared.mimeType),
                detectedSourceLanguage: nil,
                targetLanguage: settings.primaryTargetLanguage,
                systemPrompt: systemPrompt,
                maxOutputTokens: 4096
            )
            let provider = OpenAICompatibleProvider(
                baseURL: settings.baseURL,
                apiKey: apiKey,
                model: settings.model,
                firstByteTimeout: 20,
                totalTimeout: 60
            )

            let start = Date()
            var accumulated = ""
            var deltaCount = 0
            for try await delta in provider.translate(request: request) {
                if deltaCount == 0 {
                    log.notice("first delta after \(Date().timeIntervalSince(start), privacy: .public)s")
                }
                deltaCount += 1
                accumulated += delta
                translatedText = accumulated
            }
            log.notice("stream finished after \(Date().timeIntervalSince(start), privacy: .public)s, \(deltaCount, privacy: .public) deltas, \(accumulated.count, privacy: .public) chars")
            translatedText = ResponseSanitizer.sanitize(accumulated, original: "")
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
#endif
