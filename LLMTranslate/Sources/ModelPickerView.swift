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
                        .padding()
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
            models = try await provider.listModels()
        } catch let error as TranslationError {
            errorMessage = error.localizedUserMessage
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}
