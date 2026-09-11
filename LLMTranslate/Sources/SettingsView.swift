import SwiftUI
import LLMTranslateKit

/// Раздел 13 ТЗ v1.2: хост-приложение — пять минимальных экранов. Этот файл
/// — точка входа (домашнее меню) плюс общие подэкраны слотов/промптов,
/// переиспользуемые из `LanguagesAndPromptsView`.
struct SettingsView: View {
    private let settings = LLMTranslateSettings(appGroupSuiteName: SharedIdentifiers.appGroup)

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Как начать") {
                    OnboardingView()
                }
                NavigationLink("Модели") {
                    ModelsHomeView(settings: settings)
                }
                NavigationLink("Языки и промпты") {
                    LanguagesAndPromptsView(settings: settings)
                }
                NavigationLink("Отладка и расход") {
                    DebugAndUsageView(settings: settings)
                }
            }
            .navigationTitle("BYO Translate")
        }
    }
}

/// Раздел 13, экран 2 ТЗ v1.2: два слота модели — просто список входов в
/// `SlotSettingsView`, без собственной логики.
private struct ModelsHomeView: View {
    let settings: LLMTranslateSettings?

    var body: some View {
        Form {
            NavigationLink("Рабочая модель (working)") {
                SlotSettingsView(slot: .working, title: "Рабочая модель", settings: settings)
            }
            NavigationLink("Сильная модель (strong)") {
                SlotSettingsView(slot: .strong, title: "Сильная модель", settings: settings)
            }
        }
        .navigationTitle("Модели")
    }
}

/// Раздел 11.2/12.2 ТЗ v1.2: настройки одного слота — провайдер, base URL,
/// модель, ключ, флаг мультимодальности, кнопка «Проверить».
private struct SlotSettingsView: View {
    let slot: SlotID
    let title: String
    let settings: LLMTranslateSettings?

    private let keychain = KeychainStore()

    @State private var providerID: ProviderID = .openAICompatible
    @State private var baseURLString: String = OpenAICompatibleProvider.defaultBaseURL.absoluteString
    @State private var model: String = ""
    @State private var supportsImages: Bool = false
    @State private var apiKeyInput: String = ""
    @State private var storedKeyPreview: String?
    @State private var validationState: ValidationState = .idle
    @State private var isShowingModelPicker = false

    private enum ValidationState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Провайдер") {
                Picker("Провайдер", selection: $providerID) {
                    ForEach(ProviderFactory.allProviders, id: \.self) { id in
                        Text(ProviderFactory.displayName(for: id)).tag(id)
                    }
                }
                .onChange(of: providerID) { _, newValue in
                    // Раздел 6.4, п. 1 ТЗ: baseURL настраиваемый, но при
                    // смене провайдера подставляем его дефолт как отправную
                    // точку — молчаливо оставлять URL прежнего провайдера
                    // почти наверняка ошибка пользователя.
                    baseURLString = ProviderFactory.defaultBaseURL(for: newValue).absoluteString
                }
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

            Section {
                Button("Сохранить") { save() }
                Button("Проверить") { Task { await validate() } }
                    .disabled(validationState == .running)
            }

            switch validationState {
            case .idle: EmptyView()
            case .running: Section { ProgressView() }
            case let .success(text): Section("Результат") { Text(text) }
            case let .failure(message): Section("Ошибка") { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        .onAppear(perform: load)
        .sheet(isPresented: $isShowingModelPicker) {
            ModelPickerView(providerID: providerID, currentAPIKey: currentAPIKeyForListing(), baseURL: resolvedBaseURL()) { descriptor in
                model = descriptor.rawID
                if let known = descriptor.supportsImages {
                    supportsImages = known
                }
                isShowingModelPicker = false
            }
        }
    }

    private func resolvedBaseURL() -> URL {
        URL(string: baseURLString) ?? ProviderFactory.defaultBaseURL(for: providerID)
    }

    private func currentAPIKeyForListing() -> String? {
        if !apiKeyInput.isEmpty { return apiKeyInput }
        return (try? keychain.apiKey(slot: slot)) ?? nil
    }

    private func load() {
        guard let settings else { return }
        let config = settings.slot(slot)
        providerID = config.providerID
        baseURLString = config.baseURL.absoluteString
        model = config.model
        supportsImages = config.supportsImages
        if let key = (try? keychain.apiKey(slot: slot)) ?? nil, !key.isEmpty {
            storedKeyPreview = KeychainStore.maskedPreview(key)
        }
    }

    private func save() {
        guard let settings else { return }
        let config = settings.slot(slot)
        config.providerID = providerID
        if let url = URL(string: baseURLString) {
            config.baseURL = url
        }
        config.model = model
        config.supportsImages = supportsImages

        if !apiKeyInput.isEmpty {
            try? keychain.setAPIKey(apiKeyInput, slot: slot)
            storedKeyPreview = KeychainStore.maskedPreview(apiKeyInput)
            apiKeyInput = ""
        }

        // Раздел 11.4 ТЗ: «Кэш полностью очищается при смене любого слота,
        // модели или системного промпта».
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }

    /// Раздел 12, экран 2 ТЗ: «Проверить» → тестовый перевод "Hello, world".
    private func validate() async {
        save()
        guard let apiKey = (try? keychain.apiKey(slot: slot)) ?? nil, !apiKey.isEmpty else {
            validationState = .failure(TranslationError.missingAPIKey.localizedUserMessage)
            return
        }
        validationState = .running
        guard let provider = ProviderFactory.make(providerID: providerID, baseURL: resolvedBaseURL(), apiKey: apiKey, model: model) else {
            validationState = .failure("Провайдер не поддерживается")
            return
        }
        do {
            let capabilities = try await provider.validate()
            let format = NSLocalizedString("Модель %@ отвечает.", comment: "")
            validationState = .success(String(format: format, capabilities.modelID))
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
/// ввода в `SlotSettingsView`, никогда не единственный путь.
private struct ModelPickerView: View {
    let providerID: ProviderID
    let currentAPIKey: String?
    let baseURL: URL
    let onSelect: (ModelDescriptor) -> Void

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

/// Раздел 8.1/8.3/12.3 ТЗ v1.2: редактор одного промпта с кнопкой «сбросить
/// к исходному». `nil` в настройках — используется дефолт из `PromptBuilder`.
/// Не `private` — переиспользуется из `LanguagesAndPromptsView`.
struct PromptEditorView: View {
    let title: String
    let defaultText: String
    let get: () -> String?
    let set: (String?) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(4)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Готово") {
                    set(text == defaultText ? nil : text)
                    dismiss()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Сбросить к исходному") { text = defaultText }
            }
        }
        .onAppear { text = get() ?? defaultText }
    }
}

#Preview {
    SettingsView()
}
