#if canImport(UIKit)
import Foundation
import os.log

private let log = Logger(subsystem: "com.tyrex.llmtranslate", category: "translation-session")

/// Раздел 9/10.8/11.2/11.3 ТЗ v1.2. Общий пайплайн «настройки → слот →
/// провайдер → режим/промпт → стрим → разбор `⟦NOTES⟧` → санитизация»,
/// вынесенный из `TranslateSheetView`/`ImageTranslationView`, чтобы слоты,
/// эскалация и режимы не дублировались в двух местах дважды.
@MainActor
public final class TranslationSession: ObservableObject {
    @Published public private(set) var translation = ""
    @Published public private(set) var notes: [String] = []
    @Published public private(set) var isTranslating = false
    @Published public private(set) var currentError: TranslationError?
    /// Каким слотом сделан текущий результат — для подписи под переводом
    /// после эскалации (раздел 11.2 ТЗ).
    @Published public private(set) var usedSlot: SlotID?

    private let appGroupSuiteName: String
    private let keychain = KeychainStore()
    private var lastContext: RunContext?
    private var lastMode: TranslationMode = .plain

    // `nonisolated`: только сохраняет строку, изолированного состояния не
    // трогает — нужен вызываемым из незолированных контекстов (SDK-замыкание
    // TranslationUIProvider, см. TranslateExtension.swift).
    public nonisolated init(appGroupSuiteName: String) {
        self.appGroupSuiteName = appGroupSuiteName
    }

    /// Раздел 11.2 ТЗ: «Если `strong` не настроен, кнопка скрыта»; «повторное
    /// нажатие на уже эскалированном результате ничего не делает — кнопка
    /// исчезает» — оба условия здесь.
    public var canEscalate: Bool {
        guard lastContext != nil, usedSlot == .working, currentError == nil else { return false }
        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName) else { return false }
        return settings.slot(.strong).isConfigured
    }

    public var canRequestNotes: Bool {
        lastContext != nil && currentError == nil
    }

    private struct RunContext {
        let payload: Payload
        let originalText: String
        let detectedSourceLanguage: Locale.Language?
        let targetLanguage: Locale.Language
        let isImage: Bool
        let initialMode: TranslationMode
    }

    // MARK: - Public entry points

    /// Раздел 9 ТЗ: точка входа для `TranslationUIProvider`/F1.
    public func startText(_ text: String) async {
        guard !text.isEmpty else { return }
        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName) else {
            fail(.other(code: nil, message: "App Group не сконфигурирована"))
            return
        }
        let pair = LocalLanguageDetector.resolvePair(
            for: text,
            primaryTarget: settings.primaryTargetLanguage,
            secondaryTarget: settings.secondaryTargetLanguage
        )
        let mode = TranslationModeResolver.resolve(
            text: text,
            dictionaryModeEnabled: settings.dictionaryModeEnabled,
            notesMode: settings.notesMode
        )
        let context = RunContext(
            payload: .text(text),
            originalText: text,
            detectedSourceLanguage: pair.detectedSourceLanguage,
            targetLanguage: pair.targetLanguage,
            isImage: false,
            initialMode: mode
        )
        await run(context: context, mode: mode, slot: .working)
    }

    /// Раздел 10.6/10.8 ТЗ: точка входа для E1/E2/E3 — язык всегда
    /// `primaryTarget`, локальное определение языка не выполняется.
    public func startImage(_ sourceData: Data) async {
        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName) else {
            fail(.other(code: nil, message: "App Group не сконфигурирована"))
            return
        }
        do {
            // Раздел 10.7 ТЗ: подготовка (даунскейл/кодирование/лимит payload).
            let prepared = try ImagePreparation.prepare(sourceData: sourceData)
            let mode: TranslationMode = settings.notesMode == .always ? .withNotes : .plain
            let context = RunContext(
                payload: .image(prepared.data, mime: prepared.mimeType),
                originalText: "",
                detectedSourceLanguage: nil,
                targetLanguage: settings.primaryTargetLanguage,
                isImage: true,
                initialMode: mode
            )
            await run(context: context, mode: mode, slot: .working)
        } catch let error as TranslationError {
            fail(error)
        } catch {
            fail(.other(code: nil, message: String(describing: error)))
        }
    }

    /// Раздел 11.2 ТЗ: повторяет тот же запрос на `strong`.
    public func escalateToStrong() async {
        guard canEscalate, let context = lastContext else { return }
        await run(context: context, mode: lastMode, slot: .strong)
    }

    /// Раздел 11.3 ТЗ: «Пояснить» — второй запрос в `.withNotes` по тому же
    /// исходному тексту, тем же слотом, что дал текущий результат.
    public func requestNotes() async {
        guard canRequestNotes, let context = lastContext else { return }
        await run(context: context, mode: .withNotes, slot: usedSlot ?? .working)
    }

    /// «Ещё раз» (раздел 10.8 ТЗ) — полный перезапуск с исходным режимом на
    /// `working`, а не повтор последнего (эскалированного/с пояснениями) состояния.
    public func retry() async {
        guard let context = lastContext else { return }
        await run(context: context, mode: context.initialMode, slot: .working)
    }

    // MARK: - Shared pipeline

    private func run(context: RunContext, mode: TranslationMode, slot slotID: SlotID) async {
        translation = ""
        notes = []
        currentError = nil
        usedSlot = nil
        isTranslating = true
        defer { isTranslating = false }

        // Запоминаем контекст до попытки, не только при успехе — иначе
        // «Ещё раз»/«Точнее»/«Пояснить» после первой же неудачи (например,
        // не задан ключ) молча ничего не делают вместо повторной попытки.
        lastContext = context
        lastMode = mode

        guard let settings = LLMTranslateSettings(appGroupSuiteName: appGroupSuiteName) else {
            fail(.other(code: nil, message: "App Group не сконфигурирована"))
            return
        }
        let slot = settings.slot(slotID)
        guard !slot.model.isEmpty else {
            fail(.other(code: nil, message: "Модель не выбрана в настройках"))
            return
        }
        if context.isImage, !slot.supportsImages {
            // Раздел 10.6 ТЗ: при выключенном флаге — понятная ошибка, не
            // попытка вызвать API вслепую.
            fail(.modelDoesNotSupportImages)
            return
        }
        guard let apiKey = (try? keychain.apiKey(slot: slotID)) ?? nil, !apiKey.isEmpty else {
            fail(.missingAPIKey)
            return
        }

        let firstByteTimeout: TimeInterval = context.isImage ? 20 : 8
        let totalTimeout: TimeInterval = context.isImage ? 60 : 30
        guard let provider = Self.makeProvider(
            slot: slot,
            apiKey: apiKey,
            firstByteTimeout: firstByteTimeout,
            totalTimeout: totalTimeout
        ) else {
            fail(.other(code: nil, message: "Провайдер не поддерживается"))
            return
        }

        let basePromptText = context.isImage
            ? (settings.customImagePrompt ?? PromptBuilder.defaultImageSystemPrompt)
            : (settings.customTextPrompt ?? PromptBuilder.defaultTextSystemPrompt)
        let notesAddendum = settings.customNotesAddendum ?? PromptBuilder.defaultNotesAddendum
        let systemPrompt = PromptBuilder.systemPrompt(
            for: mode,
            basePromptText: basePromptText,
            notesAddendum: notesAddendum,
            targetLanguage: context.targetLanguage,
            glossary: [:]
        )

        let request = TranslationRequest(
            payload: context.payload,
            detectedSourceLanguage: context.detectedSourceLanguage,
            targetLanguage: context.targetLanguage,
            mode: mode,
            systemPrompt: systemPrompt,
            maxOutputTokens: context.isImage ? 4096 : 2048
        )

        log.notice("translate start: slot=\(slotID.rawValue, privacy: .public) provider=\(slot.providerID.rawValue, privacy: .public) model=\(slot.model, privacy: .public) mode=\(String(describing: mode), privacy: .public)")

        var markerParser = NotesMarkerParser()
        var rawTranslation = ""
        var rawNotes = ""
        let start = Date()
        var deltaCount = 0
        do {
            for try await event in provider.stream(request: request) {
                guard case let .delta(text) = event else { continue }
                if deltaCount == 0 {
                    log.notice("first delta after \(Date().timeIntervalSince(start), privacy: .public)s")
                }
                deltaCount += 1
                let (translationPart, notesPart) = markerParser.feed(text)
                rawTranslation += translationPart
                rawNotes += notesPart
                translation = rawTranslation
            }
            let (translationPart, notesPart) = markerParser.finish()
            rawTranslation += translationPart
            rawNotes += notesPart
            log.notice("stream finished after \(Date().timeIntervalSince(start), privacy: .public)s, \(deltaCount, privacy: .public) deltas")

            let sanitized = ResponseSanitizer.sanitize(rawTranslation, original: context.originalText)
            guard !sanitized.isEmpty else {
                fail(.emptyResponse)
                return
            }
            translation = sanitized
            notes = Self.splitNotes(rawNotes)
            usedSlot = slotID
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

    /// Раздел 8.7, п. 3 ТЗ: комментарии разбиваются по строкам, ведущее
    /// «— » срезается, пустые строки отбрасываются.
    private static func splitNotes(_ raw: String) -> [String] {
        raw
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("— ") {
                    trimmed = String(trimmed.dropFirst(2))
                } else if trimmed.hasPrefix("—") {
                    trimmed = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
    }

    private static func makeProvider(
        slot: ModelSlotConfig,
        apiKey: String,
        firstByteTimeout: TimeInterval,
        totalTimeout: TimeInterval
    ) -> (any TranslationProvider)? {
        ProviderFactory.make(
            providerID: slot.providerID,
            baseURL: slot.baseURL,
            apiKey: apiKey,
            model: slot.model,
            firstByteTimeout: firstByteTimeout,
            totalTimeout: totalTimeout
        )
    }
}
#endif
