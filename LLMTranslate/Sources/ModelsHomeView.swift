import SwiftUI
import LLMTranslateKit

/// Раздел 13, экран 2 ТЗ v1.2 + B5: коллекция подключений (профилей) и два
/// слота модели. Показываются только добавленные профили; новый добавляется
/// мастером (`ConnectionWizardView`).
struct ModelsHomeView: View {
    let settings: LLMTranslateSettings?

    @State private var isShowingWizard = false
    /// Любое изменение настроек в подэкранах — перечитать список при возврате.
    @State private var refreshTick = 0

    private var profiles: [ConnectionProfile] { settings?.connectionProfiles ?? [] }

    var body: some View {
        Form {
            Section("Подключения") {
                ForEach(profiles) { profile in
                    NavigationLink {
                        ProfileDetailView(profileID: profile.id, settings: settings)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                            Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button { isShowingWizard = true } label: {
                    Label("Добавить подключение", systemImage: "plus")
                }
            }

            Section("Модели") {
                NavigationLink {
                    SlotSettingsView(slot: .working, title: "Рабочая модель", settings: settings)
                } label: {
                    SlotRow(title: "Рабочая модель (working)", slot: .working, settings: settings)
                }
                NavigationLink {
                    SlotSettingsView(slot: .strong, title: "Сильная модель", settings: settings)
                } label: {
                    SlotRow(title: "Сильная модель (strong)", slot: .strong, settings: settings)
                }
            }
        }
        .id(refreshTick)
        .navigationTitle("Модели")
        .onAppear { refreshTick += 1 }
        .sheet(isPresented: $isShowingWizard, onDismiss: { refreshTick += 1 }) {
            ConnectionWizardView(settings: settings)
        }
    }
}

/// Строка слота: заголовок и «подключение · модель».
private struct SlotRow: View {
    let title: LocalizedStringKey
    let slot: SlotID
    let settings: LLMTranslateSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let settings, settings.slot(slot).isConfigured {
                let config = settings.slot(slot)
                let name = config.profileID.flatMap { settings.profile(id: $0)?.displayName }
                    ?? ProviderFactory.displayName(for: config.providerID)
                Text("\(name) · \(config.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Не настроена")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Подключение (профиль)

/// Один профиль: ключ, адрес (для Custom), проверка, удаление.
struct ProfileDetailView: View {
    let profileID: UUID
    let settings: LLMTranslateSettings?

    private let keychain = KeychainStore()
    @Environment(\.dismiss) private var dismiss

    @State private var profile: ConnectionProfile?
    @State private var baseURLString = ""
    @State private var apiKeyInput = ""
    @State private var storedKeyPreview: String?
    @State private var checkState: CheckState = .idle
    @State private var isConfirmingDelete = false

    private enum CheckState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            if let profile {
                if profile.preset == .custom {
                    Section("Сервер") {
                        Picker("Тип API", selection: providerBinding) {
                            ForEach(ProviderFactory.allProviders, id: \.self) { id in
                                Text(ProviderFactory.displayName(for: id)).tag(id)
                            }
                        }
                        TextField("Base URL", text: $baseURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }

                Section("API-ключ") {
                    if let storedKeyPreview {
                        LabeledContent("Сохранён", value: storedKeyPreview)
                    }
                    SecureField("Новый ключ", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Сохранить") { save() }
                    Button("Проверить подключение") { Task { await check() } }
                        .disabled(checkState == .running)
                }

                switch checkState {
                case .idle: EmptyView()
                case .running: Section { ProgressView() }
                case let .success(text): Section("Результат") { Text(text) }
                case let .failure(message): Section("Ошибка") { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button("Удалить подключение", role: .destructive) { isConfirmingDelete = true }
                } footer: {
                    Text("Слоты моделей, которые используют это подключение, станут не настроенными.")
                }
            }
        }
        .navigationTitle(profile?.displayName ?? "")
        .onAppear(perform: load)
        .confirmationDialog("Удалить подключение?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                settings?.removeProfile(id: profileID, keychain: keychain)
                TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
                dismiss()
            }
        }
    }

    private var providerBinding: Binding<ProviderID> {
        Binding(
            get: { profile?.providerID ?? .openAICompatible },
            set: { profile?.providerID = $0 }
        )
    }

    private func load() {
        guard let settings, let loaded = settings.profile(id: profileID) else { return }
        profile = loaded
        baseURLString = loaded.baseURL.absoluteString
        if let key = (try? keychain.apiKey(profile: profileID)) ?? nil, !key.isEmpty {
            storedKeyPreview = KeychainStore.maskedPreview(key)
        }
    }

    private func save() {
        guard let settings, var updated = profile else { return }
        if updated.preset == .custom, let url = URL(string: baseURLString), url.scheme?.hasPrefix("http") == true {
            updated.baseURL = url
        }
        profile = updated
        settings.upsert(updated)
        if !apiKeyInput.isEmpty {
            try? keychain.setAPIKey(apiKeyInput, profile: profileID)
            storedKeyPreview = KeychainStore.maskedPreview(apiKeyInput)
            apiKeyInput = ""
        }
        // Раздел 11.4 ТЗ: кэш очищается при смене слота/модели/подключения.
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }

    private func check() async {
        save()
        guard let profile else { return }
        guard let key = (try? keychain.apiKey(profile: profileID)) ?? nil, !key.isEmpty else {
            checkState = .failure(TranslationError.missingAPIKey.localizedUserMessage)
            return
        }
        checkState = .running
        guard let provider = ProviderFactory.make(providerID: profile.providerID, baseURL: profile.baseURL, apiKey: key, model: "") else {
            checkState = .failure(String(localized: "Провайдер не поддерживается"))
            return
        }
        do {
            let models = try await provider.listModels()
            checkState = .success(String(localized: "Подключение работает. Моделей в списке: \(models.count)"))
        } catch let error as TranslationError {
            checkState = .failure(error.localizedUserMessage)
        } catch {
            checkState = .failure(String(describing: error))
        }
    }
}

// MARK: - Слот модели

/// Раздел 11.2/12.2 ТЗ v1.2 + B5: слот = подключение (профиль) + модель.
struct SlotSettingsView: View {
    let slot: SlotID
    let title: LocalizedStringKey
    let settings: LLMTranslateSettings?

    private let keychain = KeychainStore()

    @State private var profileID: UUID?
    @State private var model = ""
    @State private var supportsImages = false
    @State private var disableReasoning = false
    @State private var isLegacy = false
    @State private var validationState: ValidationState = .idle
    @State private var isShowingModelPicker = false
    @State private var isShowingWizard = false
    @State private var refreshTick = 0

    private enum ValidationState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    private var profiles: [ConnectionProfile] { settings?.connectionProfiles ?? [] }

    var body: some View {
        Form {
            Section("Подключение") {
                if profiles.isEmpty {
                    Text("Сначала добавьте подключение к провайдеру.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Подключение", selection: $profileID) {
                        Text("Не выбрано").tag(UUID?.none)
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(UUID?.some(profile.id))
                        }
                    }
                }
                Button { isShowingWizard = true } label: {
                    Label("Добавить подключение", systemImage: "plus")
                }
                if isLegacy, profileID == nil {
                    Text("Слот настроен вручную до появления подключений. Выберите подключение, чтобы перейти на него.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Модель") {
                ModelChoiceFields(
                    model: $model,
                    supportsImages: $supportsImages,
                    disableReasoning: isOpenRouterSelected ? $disableReasoning : nil
                ) {
                    isShowingModelPicker = true
                }
            }

            Section {
                Button("Сохранить") { save() }
                Button("Проверить") { Task { await validate() } }
                    .disabled(validationState == .running || model.isEmpty)
            }

            switch validationState {
            case .idle: EmptyView()
            case .running: Section { ProgressView() }
            case let .success(text): Section("Результат") { Text(text) }
            case let .failure(message): Section("Ошибка") { Text(message).foregroundStyle(.red) }
            }
        }
        .id(refreshTick)
        .navigationTitle(title)
        .onAppear(perform: load)
        .sheet(isPresented: $isShowingWizard, onDismiss: { refreshTick += 1; load() }) {
            ConnectionWizardView(settings: settings)
        }
        .sheet(isPresented: $isShowingModelPicker) {
            let connection = activeConnection()
            ModelPickerView(providerID: connection.providerID, currentAPIKey: connection.apiKey, baseURL: connection.baseURL) { descriptor in
                model = descriptor.rawID
                supportsImages = descriptor.supportsImages ?? supportsImages
                // Рейтинг знает, каким моделям размышление мешает с нашим лимитом ответа.
                disableReasoning = isOpenRouterSelected
                    && ModelRatings.rating(for: descriptor.rawID)?.disableReasoningRecommended == true
                isShowingModelPicker = false
            }
        }
    }

    private var isOpenRouterSelected: Bool {
        guard let profileID else { return false }
        return settings?.profile(id: profileID)?.preset == .openRouter
    }

    /// Подключение по текущему выбору в форме (ещё не сохранённому).
    private func activeConnection() -> ResolvedConnection {
        guard let settings else {
            return ResolvedConnection(providerID: .openAICompatible, baseURL: OpenAICompatibleProvider.defaultBaseURL, apiKey: nil)
        }
        if let profileID, let profile = settings.profile(id: profileID) {
            return ResolvedConnection(
                providerID: profile.providerID,
                baseURL: profile.baseURL,
                apiKey: (try? keychain.apiKey(profile: profileID)) ?? nil
            )
        }
        return settings.connection(for: slot, keychain: keychain)
    }

    private func load() {
        guard let settings else { return }
        let config = settings.slot(slot)
        profileID = config.profileID.flatMap { settings.profile(id: $0)?.id }
        model = config.model
        supportsImages = config.supportsImages
        disableReasoning = config.disableReasoning
        isLegacy = config.isConfigured && config.profileID == nil
    }

    private func save() {
        guard let settings else { return }
        let config = settings.slot(slot)
        if let profileID, let profile = settings.profile(id: profileID) {
            config.profileID = profile.id
            config.providerID = profile.providerID
            config.baseURL = profile.baseURL
            isLegacy = false
        } else {
            config.profileID = nil
        }
        config.model = model
        config.supportsImages = supportsImages
        config.disableReasoning = disableReasoning && isOpenRouterSelected
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }

    /// Раздел 12, экран 2 ТЗ: «Проверить» → тестовый перевод.
    private func validate() async {
        save()
        let connection = activeConnection()
        guard let apiKey = connection.apiKey, !apiKey.isEmpty else {
            validationState = .failure(TranslationError.missingAPIKey.localizedUserMessage)
            return
        }
        validationState = .running
        guard let provider = ProviderFactory.make(providerID: connection.providerID, baseURL: connection.baseURL, apiKey: apiKey, model: model) else {
            validationState = .failure(String(localized: "Провайдер не поддерживается"))
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

/// Поле модели со списком и флагом «понимает изображения» — общее для слота и
/// мастера.
struct ModelChoiceFields: View {
    @Binding var model: String
    @Binding var supportsImages: Bool
    /// `nil` — переключатель не показывается (он нужен только для OpenRouter).
    var disableReasoning: Binding<Bool>?
    let onPickFromList: () -> Void

    var body: some View {
        HStack {
            TextField("Модель", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Список", action: onPickFromList)
                .buttonStyle(.borderless)
        }
        if let rating = ModelRatings.rating(for: model) {
            Text("Рейтинг «лучше»: \(rating.score) из 100")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Toggle("Модель понимает изображения", isOn: $supportsImages)
        if let disableReasoning {
            Toggle("Отключить размышление", isOn: disableReasoning)
            Text("Для моделей, которые «размышляют» перед ответом (например, Qwen): без этого весь лимит ответа может уйти на рассуждения, и перевод придёт пустым. Работает только через OpenRouter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
