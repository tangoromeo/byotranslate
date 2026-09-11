import SwiftUI
import LLMTranslateKit

/// Минимальные настройки этапа 1 (раздел 16 ТЗ: «LLMTranslateKit, Keychain,
/// OpenAI-совместимый адаптер со стримингом, ... минимальные настройки»).
/// Полный пятиэкранный хост-интерфейс раздела 12 ТЗ — этап 5.
struct SettingsView: View {
    private let settings = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup)
    private let keychain = KeychainStore()

    @State private var baseURLString: String = OpenAICompatibleProvider.defaultBaseURL.absoluteString
    @State private var model: String = ""
    @State private var primaryTargetCode: String = "ru"
    @State private var secondaryTargetCode: String = "en"
    /// Раздел 6.3 ТЗ: ручной флаг — единственный источник истины, когда
    /// список моделей недоступен или сам провайдер не публикует
    /// модальности (голый OpenAI API, Ollama, LM Studio). Когда модель
    /// выбрана из списка и он сообщает модальность (например, OpenRouter),
    /// значение подставляется автоматически в `ModelPickerView.onSelect`
    /// — пользователю нечего гадать.
    @State private var supportsImages: Bool = false

    @State private var apiKeyInput: String = ""
    @State private var storedKeyPreview: String?

    @State private var validationState: ValidationState = .idle
    @State private var isShowingModelPicker = false

    private enum ValidationState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Провайдер") {
                    LabeledContent("Тип") { Text("OpenAI-совместимый") }
                    TextField("Base URL", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("Модель", text: $model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Список") { isShowingModelPicker = true }
                            .buttonStyle(.borderless)
                    }
                    // Раздел 6.3 ТЗ: «флаг «модель поддерживает изображения»» —
                    // fallback на случай, когда список моделей недоступен или
                    // не публикует модальности (см. ModelPickerView).
                    Toggle("Модель понимает изображения", isOn: $supportsImages)
                }

                Section("API-ключ") {
                    if let storedKeyPreview {
                        LabeledContent("Сохранён", value: storedKeyPreview)
                    }
                    SecureField("sk-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Языки") {
                    TextField("Основной целевой (BCP-47, напр. ru)", text: $primaryTargetCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Вторичный целевой (BCP-47, напр. en)", text: $secondaryTargetCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Сохранить") { save() }
                    Button("Проверить") { Task { await validate() } }
                        .disabled(validationState == .running)
                }

                switch validationState {
                case .idle:
                    EmptyView()
                case .running:
                    Section { ProgressView() }
                case let .success(text):
                    Section("Результат") { Text(text) }
                case let .failure(message):
                    Section("Ошибка") {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("LLMTranslate")
            .onAppear(perform: load)
            .sheet(isPresented: $isShowingModelPicker) {
                ModelPickerView(currentAPIKey: currentAPIKeyForListing(), baseURL: resolvedBaseURL()) { descriptor in
                    model = descriptor.rawID
                    // Раздел 6.3 ТЗ: если провайдер сам знает модальность
                    // (OpenRouter) — не спрашивать пользователя повторно.
                    // Если не знает (`nil`) — ручной тумблер остаётся как был.
                    if let known = descriptor.supportsImages {
                        supportsImages = known
                    }
                    isShowingModelPicker = false
                }
            }
        }
    }

    private func resolvedBaseURL() -> URL {
        URL(string: baseURLString) ?? OpenAICompatibleProvider.defaultBaseURL
    }

    private func currentAPIKeyForListing() -> String? {
        guard let settings else { return apiKeyInput.isEmpty ? nil : apiKeyInput }
        if !apiKeyInput.isEmpty { return apiKeyInput }
        return (try? keychain.apiKey(provider: settings.providerID)) ?? nil
    }

    private func load() {
        guard let settings else { return }
        baseURLString = settings.baseURL.absoluteString
        model = settings.model
        primaryTargetCode = settings.primaryTargetLanguage.minimalIdentifier
        secondaryTargetCode = settings.secondaryTargetLanguage.minimalIdentifier
        supportsImages = settings.supportsImages
        if let key = (try? keychain.apiKey(provider: settings.providerID)) ?? nil, !key.isEmpty {
            storedKeyPreview = KeychainStore.maskedPreview(key)
        }
    }

    private func save() {
        guard let settings else { return }
        if let url = URL(string: baseURLString) {
            settings.baseURL = url
        }
        settings.model = model
        settings.primaryTargetLanguage = Locale.Language(identifier: primaryTargetCode)
        settings.secondaryTargetLanguage = Locale.Language(identifier: secondaryTargetCode)
        settings.supportsImages = supportsImages

        if !apiKeyInput.isEmpty {
            try? keychain.setAPIKey(apiKeyInput, provider: settings.providerID)
            storedKeyPreview = KeychainStore.maskedPreview(apiKeyInput)
            apiKeyInput = ""
        }
    }

    /// Раздел 12, экран 2 ТЗ: «Проверить» → тестовый перевод "Hello, world".
    private func validate() async {
        save()
        guard let settings else { return }
        guard let apiKey = (try? keychain.apiKey(provider: settings.providerID)) ?? nil, !apiKey.isEmpty else {
            validationState = .failure(TranslationError.missingAPIKey.localizedUserMessage)
            return
        }
        validationState = .running
        let provider = OpenAICompatibleProvider(baseURL: settings.baseURL, apiKey: apiKey, model: settings.model)
        do {
            let capabilities = try await provider.validate()
            validationState = .success("Модель \(capabilities.modelID) отвечает.")
        } catch let error as TranslationError {
            validationState = .failure(error.localizedUserMessage)
        } catch {
            validationState = .failure(String(describing: error))
        }
    }
}

/// Раздел 6.4, п. 2 ТЗ: «Список для выпадающего меню тянуть через
/// listModels(). Если запрос списка не удался — оставить свободный ввод
/// строки». Эта шторка — только дополнительное удобство поверх свободного
/// ввода в `SettingsView`, никогда не единственный путь.
private struct ModelPickerView: View {
    let currentAPIKey: String?
    let baseURL: URL
    let onSelect: (ModelDescriptor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelDescriptor] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""

    private var filteredModels: [ModelDescriptor] {
        guard !query.isEmpty else { return models }
        return models.filter { $0.rawID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
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
                    .searchable(text: $query)
                }
            }
            .navigationTitle("Модели")
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
        let provider = OpenAICompatibleProvider(baseURL: baseURL, apiKey: currentAPIKey, model: "")
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

#Preview {
    SettingsView()
}
