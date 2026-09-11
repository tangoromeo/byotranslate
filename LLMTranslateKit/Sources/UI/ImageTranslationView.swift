#if canImport(UIKit)
import SwiftUI
import UIKit

/// Раздел 10.3/10.8 ТЗ: «Тот же UI результата, что и в остальных точках
/// входа — общий SwiftUI-компонент из LLMTranslateKit». Используется из
/// `LLMTranslateShareExt` и из App Intents/Control (этап 5).
///
/// Полноэкранный результат: миниатюра исходника сверху (тап — просмотр
/// оригинала), перевод потоком, «Копировать»/«Поделиться»/«Точнее»/
/// «Пояснить»/«Ещё раз». Кнопки «Заменить» нет — заменять нечего (10.8 ТЗ).
public struct ImageTranslationView: View {
    private let originalImageData: Data

    @StateObject private var session: TranslationSession
    @State private var isShowingOriginal = false
    @State private var isShowingDetails = false
    @State private var isShowingNotes = false
    @State private var copiedFeedback = false

    /// Раздел 9 ТЗ (строка 410): иврит/арабский результат — по правому краю.
    private var isRTLResult: Bool {
        session.lastTargetLanguage.map(TextDirectionResolver.isRightToLeft) ?? false
    }

    public init(originalImageData: Data, appGroupSuiteName: String) {
        self.originalImageData = originalImageData
        _session = StateObject(wrappedValue: TranslationSession(appGroupSuiteName: appGroupSuiteName))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                thumbnail

                if let currentError = session.currentError {
                    errorSection(currentError)
                } else {
                    Text(session.translation.isEmpty ? " " : session.translation)
                        .font(.body)
                        .textSelection(.enabled)
                        .multilineTextAlignment(isRTLResult ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: isRTLResult ? .trailing : .leading)
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

                buttonRow
            }
            .padding()
        }
        .sheet(isPresented: $isShowingOriginal) {
            originalImageSheet
        }
        // `id:` обязателен: без него .task привязан к идентичности вью, не к
        // originalImageData. ContentView держит fullScreenCover открытым
        // между запусками E2/E3 — если команда срабатывает второй раз, пока
        // шторка от первого перевода ещё не закрыта, SwiftUI не пересоздаёт
        // ImageTranslationView (та же позиция в дереве), а просто обновляет
        // originalImageData на новое значение. Без id thumbnail (читает
        // originalImageData напрямую) показывает новую картинку, а
        // session.translation остаётся от предыдущей — задача не
        // перезапускается сама по себе.
        .task(id: originalImageData) { await session.startImage(originalImageData) }
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
                UIPasteboard.general.string = session.translation
                copiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
            } label: {
                Label(copiedFeedback ? "Скопировано" : "Копировать", systemImage: "doc.on.doc")
            }
            .disabled(session.translation.isEmpty)

            if !session.translation.isEmpty {
                ShareLink(item: session.translation) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }

            if session.canEscalate {
                Button { Task { await session.escalateToStrong() } } label: {
                    Label("Точнее", systemImage: "sparkles")
                }
            }
            if session.canRequestNotes {
                Button { Task { await session.requestNotes() } } label: {
                    Label("Пояснить", systemImage: "text.bubble")
                }
            }

            Button {
                Task { await session.retry() }
            } label: {
                Label("Ещё раз", systemImage: "arrow.clockwise")
            }
            .disabled(session.isTranslating)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
    }
}
#endif
