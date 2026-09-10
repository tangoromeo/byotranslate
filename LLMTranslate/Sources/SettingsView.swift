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

    @State private var apiKeyInput: String = ""
    @State private var storedKeyPreview: String?

    @State private var validationState: ValidationState = .idle

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
                    TextField("Модель", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
        }
    }

    private func load() {
        guard let settings else { return }
        baseURLString = settings.baseURL.absoluteString
        model = settings.model
        primaryTargetCode = settings.primaryTargetLanguage.minimalIdentifier
        secondaryTargetCode = settings.secondaryTargetLanguage.minimalIdentifier
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

#Preview {
    SettingsView()
}
