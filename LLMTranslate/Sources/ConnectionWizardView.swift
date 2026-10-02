import SwiftUI
import LLMTranslateKit

/// Раздел B5: мастер добавления подключения. Три шага: пресет → ключ
/// (проверяется запросом списка моделей) → рабочая и, по желанию, сильная
/// модель. В коллекции может быть не больше одного профиля на пресет, поэтому
/// уже добавленные пресеты в списке не показываются.
@MainActor
final class WizardModel: ObservableObject {
    let settings: LLMTranslateSettings?
    private let keychain = KeychainStore()

    @Published var customProvider: ProviderID = .openAICompatible
    @Published var customURL = ""
    @Published var keyInput = ""
    @Published var isChecking = false
    @Published var errorMessage: String?
    /// Что получилось после успешного шага «ключ».
    @Published private(set) var profile: ConnectionProfile?
    @Published private(set) var savedKey: String?

    @Published var workingModel = ""
    @Published var workingImages = false
    @Published var strongModel = ""
    @Published var strongImages = false

    init(settings: LLMTranslateSettings?) {
        self.settings = settings
    }

    /// Пресеты, которых в коллекции ещё нет. OpenRouter первым: один ключ даёт
    /// доступ к моделям разных компаний — проще всего начать.
    var availablePresets: [ProfilePreset] {
        let used = Set((settings?.connectionProfiles ?? []).map(\.preset))
        return [.openRouter, .openAI, .anthropic, .google, .custom].filter { !used.contains($0) }
    }

    private func makeProfile(for preset: ProfilePreset) -> ConnectionProfile? {
        if preset == .custom {
            guard let url = URL(string: customURL.trimmingCharacters(in: .whitespaces)),
                  url.scheme == "http" || url.scheme == "https", url.host != nil
            else {
                errorMessage = String(localized: "Введите адрес сервера, например https://example.com/v1")
                return nil
            }
            return ConnectionProfile.make(preset: .custom, providerID: customProvider, baseURL: url)
        }
        return ConnectionProfile.make(preset: preset)
    }

    /// Проверяет ключ запросом списка моделей; при успехе сохраняет профиль и
    /// ключ. `skipCheck` — для серверов, у которых списка моделей нет.
    func connect(preset: ProfilePreset, skipCheck: Bool = false) async -> Bool {
        errorMessage = nil
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = TranslationError.missingAPIKey.localizedUserMessage
            return false
        }
        guard let profile = makeProfile(for: preset) else { return false }

        if !skipCheck {
            isChecking = true
            defer { isChecking = false }
            guard let provider = ProviderFactory.make(providerID: profile.providerID, baseURL: profile.baseURL, apiKey: key, model: "") else {
                errorMessage = String(localized: "Провайдер не поддерживается")
                return false
            }
            do {
                _ = try await provider.listModels()
            } catch let error as TranslationError {
                errorMessage = error.localizedUserMessage
                return false
            } catch {
                errorMessage = String(describing: error)
                return false
            }
        }

        do {
            try keychain.setAPIKey(key, profile: profile.id)
        } catch {
            errorMessage = String(describing: error)
            return false
        }
        settings?.upsert(profile)
        self.profile = profile
        savedKey = key
        keyInput = ""
        // Подсказка по умолчанию: у этих провайдеров все актуальные модели
        // понимают изображения, а список этого не сообщает.
        let defaultImages = preset == .anthropic || preset == .google
        workingImages = defaultImages
        strongImages = defaultImages
        return true
    }

    func defaultImages(for descriptor: ModelDescriptor) -> Bool {
        descriptor.supportsImages ?? (profile?.preset == .anthropic || profile?.preset == .google)
    }

    /// Записывает выбранные модели в слоты. Слот без выбора не трогаем.
    func finish() {
        guard let settings, let profile else { return }
        func apply(_ slot: SlotID, model: String, images: Bool) {
            let model = model.trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { return }
            let config = settings.slot(slot)
            config.profileID = profile.id
            config.providerID = profile.providerID
            config.baseURL = profile.baseURL
            config.model = model
            config.supportsImages = images
        }
        apply(.working, model: workingModel, images: workingImages)
        apply(.strong, model: strongModel, images: strongImages)
        TranslationCache(appGroupSuiteName: SharedIdentifiers.appGroup).clear()
    }
}

struct ConnectionWizardView: View {
    @StateObject private var wizard: WizardModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    private enum Step: Hashable {
        case key(ProfilePreset)
        case models
    }

    init(settings: LLMTranslateSettings?) {
        _wizard = StateObject(wrappedValue: WizardModel(settings: settings))
    }

    var body: some View {
        NavigationStack(path: $path) {
            presetList
                .navigationTitle("Новое подключение")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case let .key(preset):
                        KeyStep(preset: preset, wizard: wizard) { path.append(.models) }
                    case .models:
                        ModelsStep(wizard: wizard) { dismiss() }
                    }
                }
        }
    }

    private var presetList: some View {
        List {
            if wizard.availablePresets.isEmpty {
                Text("Все подключения уже добавлены.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(wizard.availablePresets) { preset in
                        Button { path.append(.key(preset)) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName).foregroundStyle(.primary)
                                    Text(Self.tagline(for: preset))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("Выберите, откуда брать модели")
                }
            }
        }
    }

    private static func tagline(for preset: ProfilePreset) -> LocalizedStringKey {
        switch preset {
        case .openRouter: "Один ключ — модели разных компаний. Проще всего начать"
        case .openAI: "Модели GPT напрямую у OpenAI"
        case .anthropic: "Модели Claude напрямую у Anthropic"
        case .google: "Модели Gemini напрямую у Google"
        case .custom: "Свой сервер: Ollama, LM Studio, прокси — любой совместимый API"
        }
    }
}

// MARK: - Шаг 2: ключ

private struct KeyStep: View {
    let preset: ProfilePreset
    @ObservedObject var wizard: WizardModel
    let onConnected: () -> Void

    var body: some View {
        Form {
            if preset == .custom {
                Section("Сервер") {
                    Picker("Тип API", selection: $wizard.customProvider) {
                        ForEach(ProviderFactory.allProviders, id: \.self) { id in
                            Text(ProviderFactory.displayName(for: id)).tag(id)
                        }
                    }
                    TextField("Base URL", text: $wizard.customURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }

            Section {
                SecureField("API-ключ", text: $wizard.keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Ключ для \(preset.displayName)")
            } footer: {
                if preset == .custom {
                    Text("Ключ хранится в Keychain на этом устройстве. Для локальных серверов без ключа подойдёт любое значение.")
                } else {
                    Text("Ключ хранится в Keychain на этом устройстве и отправляется только этому провайдеру.")
                }
            }

            if let message = wizard.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    if preset == .custom {
                        Button("Сохранить без проверки") {
                            Task { if await wizard.connect(preset: preset, skipCheck: true) { onConnected() } }
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { if await wizard.connect(preset: preset) { onConnected() } }
                } label: {
                    HStack {
                        Text("Проверить и продолжить")
                        if wizard.isChecking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(wizard.isChecking || wizard.keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(preset.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { wizard.errorMessage = nil }
    }
}

// MARK: - Шаг 3: модели

private struct ModelsStep: View {
    @ObservedObject var wizard: WizardModel
    let onDone: () -> Void

    @State private var pickTarget: PickTarget?

    private enum PickTarget: Identifiable {
        case working, strong
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                ModelChoiceFields(model: $wizard.workingModel, supportsImages: $wizard.workingImages) {
                    pickTarget = .working
                }
            } header: {
                Text("Рабочая модель")
            } footer: {
                Text("Переводит выделенный текст и скриншоты — нужна быстрая и недорогая. Для скриншотов модель должна понимать изображения.")
            }

            Section {
                ModelChoiceFields(model: $wizard.strongModel, supportsImages: $wizard.strongImages) {
                    pickTarget = .strong
                }
            } header: {
                Text("Сильная модель (необязательно)")
            } footer: {
                Text("Включается кнопкой «Точнее», когда нужен более аккуратный перевод.")
            }

            Section {
                Button("Готово") {
                    wizard.finish()
                    onDone()
                }
                .disabled(wizard.workingModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Модели")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .sheet(item: $pickTarget) { target in
            if let profile = wizard.profile {
                ModelPickerView(providerID: profile.providerID, currentAPIKey: wizard.savedKey, baseURL: profile.baseURL) { descriptor in
                    let images = wizard.defaultImages(for: descriptor)
                    switch target {
                    case .working:
                        wizard.workingModel = descriptor.rawID
                        wizard.workingImages = images
                    case .strong:
                        wizard.strongModel = descriptor.rawID
                        wizard.strongImages = images
                    }
                    pickTarget = nil
                }
            }
        }
    }
}
