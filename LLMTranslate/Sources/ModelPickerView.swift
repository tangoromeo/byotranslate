import SwiftUI
import LLMTranslateKit

/// Раздел 6.4, п. 2 ТЗ: «Список для выпадающего меню тянуть через
/// listModels(). Если запрос списка не удался — оставить свободный ввод
/// строки». Эта шторка — только дополнительное удобство поверх свободного
/// ввода в `SlotSettingsView`, никогда не единственный путь.
struct ModelPickerView: View {
    let providerID: ProviderID
    let currentAPIKey: String?
    let baseURL: URL
    let onSelect: (ModelDescriptor) -> Void

    init(
        providerID: ProviderID,
        currentAPIKey: String?,
        baseURL: URL,
        imagesOnly: Bool = false,
        onSelect: @escaping (ModelDescriptor) -> Void
    ) {
        self.providerID = providerID
        self.currentAPIKey = currentAPIKey
        self.baseURL = baseURL
        self.onSelect = onSelect
        _imagesOnly = State(initialValue: imagesOnly)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelDescriptor] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""
    /// Раздел 6.3 ТЗ: фильтр, не просто бейдж — иначе список из сотен
    /// моделей (типично для OpenRouter) невозможно сузить до реально
    /// нужных, когда слот предназначен для изображений.
    @State private var imagesOnly = false

    private var filteredModels: [ModelDescriptor] {
        var result = models
        if imagesOnly {
            result = result.filter { $0.supportsImages == true }
        }
        guard !query.isEmpty else { return result }
        return result.filter { $0.rawID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Обычная подписанная строка, а не иконка в toolbar — так
                // видно текущее состояние переключателя, не только клик.
                if !isLoading, errorMessage == nil {
                    Toggle("Только с поддержкой изображений", isOn: $imagesOnly)
                        .padding([.horizontal, .top])
                    ratingCaption
                        .font(.caption)
                        .foregroundStyle(ModelRatings.isStale() ? Color.orange : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom])
                    Divider()
                }

                Group {
                    if isLoading {
                        ProgressView()
                    } else if let errorMessage {
                        ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                    } else if filteredModels.isEmpty {
                        ContentUnavailableView(
                            imagesOnly ? "Нет моделей с поддержкой изображений" : "Ничего не найдено",
                            systemImage: "magnifyingglass"
                        )
                    } else {
                        List(filteredModels) { descriptor in
                            Button {
                                onSelect(descriptor)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(descriptor.displayName ?? descriptor.rawID)
                                            .foregroundStyle(.primary)
                                        if descriptor.displayName != nil {
                                            Text(descriptor.rawID)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    ratingBadge(for: descriptor.rawID)
                                    modalityBadge(for: descriptor.supportsImages)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Модели")
            .searchable(text: $query, prompt: "Поиск модели")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { await loadModels() }
        }
    }

    /// Список отсортирован по рейтингу «лучше» (docs/RATINGS.md); дата замера
    /// видна, а устаревший рейтинг подсвечен.
    private var ratingCaption: Text {
        let date = ModelRatings.measuredDate?.formatted(date: .numeric, time: .omitted) ?? "—"
        if ModelRatings.isStale() {
            return Text("Рейтинг устарел (замер \(date)): обновится с новой версией приложения. Сначала модели с рейтингом.")
        }
        return Text("Сначала лучшие по рейтингу «лучше» (замер \(date)). Модели без оценки — внизу по алфавиту.")
    }

    @ViewBuilder
    private func ratingBadge(for rawID: String) -> some View {
        if let rating = ModelRatings.rating(for: rawID) {
            Text("\(rating.score)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.18)))
                .accessibilityLabel(Text("Рейтинг \(rating.score) из 100"))
        }
    }

    @ViewBuilder
    private func modalityBadge(for supportsImages: Bool?) -> some View {
        switch supportsImages {
        case true:
            Image(systemName: "photo").foregroundStyle(.blue)
        case false:
            Image(systemName: "text.alignleft").foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func loadModels() async {
        guard let currentAPIKey, !currentAPIKey.isEmpty else {
            errorMessage = TranslationError.missingAPIKey.localizedUserMessage
            isLoading = false
            return
        }
        guard let provider = ProviderFactory.make(providerID: providerID, baseURL: baseURL, apiKey: currentAPIKey, model: "") else {
            errorMessage = "Провайдер не поддерживается"
            isLoading = false
            return
        }
        do {
            models = ModelRatings.sorted(try await provider.listModels())
        } catch let error as TranslationError {
            errorMessage = error.localizedUserMessage
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}
