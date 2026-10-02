import SwiftUI
import LLMTranslateKit

/// Раздел 13, экран 5 ТЗ v1.2: кэш (11.4), счётчик расхода (11.5), таймауты
/// и лимит вывода, лог последних 20 запросов без ключей/текстов/изображений.
///
/// Переключатель локального OCR из ТЗ 13.5 сознательно не сделан — сама
/// функция (см. `docs/BACKLOG.md`, B3) не реализована и заблокирована на
/// невыясненном списке языков Vision OCR, тумблер для несуществующей фичи
/// хуже, чем его отсутствие.
struct DebugAndUsageView: View {
    let settings: LLMTranslateSettings?

    private let cache = TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup)
    private let usageCounter = UsageCounter(appGroupSuiteName: SharedIdentifiers.appGroup)
    private let requestLog = RequestLog(appGroupSuiteName: SharedIdentifiers.appGroup)

    @State private var cacheEnabled = false
    @State private var cacheSizeBytes = 0
    @State private var usageSummaries: [UsageCounter.Summary] = []
    @State private var textFirstByteTimeout: Double = 8
    @State private var textTotalTimeout: Double = 30
    @State private var imageFirstByteTimeout: Double = 20
    @State private var imageTotalTimeout: Double = 60
    @State private var textMaxOutputTokens = 2048
    @State private var imageMaxOutputTokens = 4096
    @State private var logEntries: [RequestLogEntry] = []

    var body: some View {
        Form {
            Section {
                Toggle("Кэшировать переводы", isOn: $cacheEnabled)
                Text("Переводы сохраняются на устройстве в зашифрованном виде на сутки, чтобы повторный перевод того же текста был мгновенным.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Размер кэша", value: cacheSizeText)
                Button("Очистить кэш") { clearCache() }
            } header: {
                Text("Кэш")
            }

            if !usageSummaries.isEmpty {
                Section {
                    ForEach(Array(usageSummaries.enumerated()), id: \.offset) { _, summary in
                        LabeledContent(usageRowTitle(summary), value: usageRowValue(summary))
                    }
                    Button("Сбросить счётчик") { resetUsage() }
                } header: {
                    Text("Расход за месяц")
                }
            }

            Section {
                LabeledContent("Текст, до первого символа (с)") {
                    TextField("", value: $textFirstByteTimeout, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Текст, общий таймаут (с)") {
                    TextField("", value: $textTotalTimeout, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Текст, лимит токенов вывода") {
                    TextField("", value: $textMaxOutputTokens, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Изображение, до первого символа (с)") {
                    TextField("", value: $imageFirstByteTimeout, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Изображение, общий таймаут (с)") {
                    TextField("", value: $imageTotalTimeout, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Изображение, лимит токенов вывода") {
                    TextField("", value: $imageMaxOutputTokens, format: .number).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Таймауты и лимиты")
            }

            if !logEntries.isEmpty {
                Section {
                    ForEach(logEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.slot.rawValue) · \(entry.providerID.rawValue) · \(entry.model)")
                                .font(.caption)
                            Text(logEntryDetail(entry))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Последние запросы")
                }
            }

            Section {
                SaveButton { save() }
            }
        }
        .navigationTitle("Отладка и расход")
        .onAppear(perform: load)
    }

    private var cacheSizeText: String {
        let bytes = cacheSizeBytes
        if bytes < 1024 { return "\(bytes) Б" }
        return String(format: "%.1f КБ", Double(bytes) / 1024)
    }

    private func usageRowTitle(_ summary: UsageCounter.Summary) -> String {
        let slotName = summary.slot == .working ? "Рабочая" : "Сильная"
        let kind = summary.isImage ? "изображения" : "текст"
        return "\(slotName), \(kind)"
    }

    private func usageRowValue(_ summary: UsageCounter.Summary) -> String {
        guard let inputTokens = summary.inputTokens, let outputTokens = summary.outputTokens else {
            return "\(summary.requestCount) — токены неизвестны"
        }
        return "\(summary.requestCount), \(inputTokens)/\(outputTokens) токенов"
    }

    private func logEntryDetail(_ entry: RequestLogEntry) -> String {
        let kind = entry.isImage ? "изображение" : "текст"
        let tokens = (entry.promptTokens, entry.completionTokens)
        let tokensText: String
        if let prompt = tokens.0, let completion = tokens.1 {
            tokensText = "\(prompt)/\(completion) токенов"
        } else {
            tokensText = "токены неизвестны"
        }
        return "\(kind), \(entry.mode), \(entry.payloadSizeBytes) Б, \(entry.latencyMs) мс, \(entry.status), \(tokensText)"
    }

    private func clearCache() {
        cache.clear()
        cacheSizeBytes = cache.currentSizeBytes
    }

    private func resetUsage() {
        usageCounter?.reset()
        usageSummaries = usageCounter?.currentMonthSummaries() ?? []
    }

    private func load() {
        guard let settings else { return }
        cacheEnabled = settings.cacheEnabled
        cacheSizeBytes = cache.currentSizeBytes
        usageSummaries = usageCounter?.currentMonthSummaries() ?? []
        textFirstByteTimeout = settings.textFirstByteTimeout
        textTotalTimeout = settings.textTotalTimeout
        imageFirstByteTimeout = settings.imageFirstByteTimeout
        imageTotalTimeout = settings.imageTotalTimeout
        textMaxOutputTokens = settings.textMaxOutputTokens
        imageMaxOutputTokens = settings.imageMaxOutputTokens
        logEntries = requestLog?.recentEntries() ?? []
    }

    private func save() {
        guard let settings else { return }
        settings.cacheEnabled = cacheEnabled
        settings.textFirstByteTimeout = textFirstByteTimeout
        settings.textTotalTimeout = textTotalTimeout
        settings.imageFirstByteTimeout = imageFirstByteTimeout
        settings.imageTotalTimeout = imageTotalTimeout
        settings.textMaxOutputTokens = textMaxOutputTokens
        settings.imageMaxOutputTokens = imageMaxOutputTokens
        cacheSizeBytes = cache.currentSizeBytes
    }
}
