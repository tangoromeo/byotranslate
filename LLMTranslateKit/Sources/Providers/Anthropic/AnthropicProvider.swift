import Foundation

/// Раздел 6.2/6.4 ТЗ v1.2, этап 2. `baseURL` настраиваемый — та же логика,
/// что у `OpenAICompatibleProvider`: прокси/корпоративные шлюзы без нового
/// кода. Стриминговая инфраструктура (byte-buffering, ретраи, классификация
/// ошибок) — общая, `Providers/Shared/SSEStreamRunner.swift`.
public final class AnthropicProvider: TranslationProvider, @unchecked Sendable {
    public let id: ProviderID = .anthropic

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let anthropicVersion: String
    private let firstByteTimeout: TimeInterval
    private let totalTimeout: TimeInterval

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        anthropicVersion: String = "2023-06-01",
        firstByteTimeout: TimeInterval = 8,
        totalTimeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.anthropicVersion = anthropicVersion
        self.firstByteTimeout = firstByteTimeout
        self.totalTimeout = totalTimeout
    }

    public static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1")!

    // MARK: - TranslationProvider

    public func stream(request: TranslationRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: TranslationError.missingAPIKey)
                return
            }
            let task = Task {
                var attempt = 0
                let yieldedAny = YieldedFlag()
                while true {
                    do {
                        let urlRequest = try buildRequest(for: request)
                        try await runOneAttempt(urlRequest: urlRequest) { event in
                            if case .delta = event { yieldedAny.markYielded() }
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch {
                        let (translationError, canRetry) = ProviderErrorClassifier.classify(error)
                        if !yieldedAny.value, attempt < 1, canRetry {
                            attempt += 1
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                        continuation.finish(throwing: translationError)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func validate() async throws -> ProviderCapabilities {
        let request = TranslationRequest(
            payload: .text("Hello, world"),
            detectedSourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "ru"),
            systemPrompt: PromptBuilder.render(
                template: PromptBuilder.defaultTextSystemPrompt,
                targetLanguage: Locale.Language(identifier: "ru"),
                glossary: [:]
            )
        )
        var receivedAny = false
        for try await event in stream(request: request) {
            if case .delta = event { receivedAny = true }
        }
        guard receivedAny else { throw TranslationError.emptyResponse }
        return ProviderCapabilities(modelID: model, supportsImages: false)
    }

    public func listModels() async throws -> [ModelDescriptor] {
        guard !apiKey.isEmpty else { throw TranslationError.missingAPIKey }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("models"))
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode
                throw RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: nil, bodyCode: nil)
            }
            struct ListResponse: Decodable {
                struct Model: Decodable { let id: String; let displayName: String?
                    enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
                }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
            return decoded.data.map { ModelDescriptor(rawID: $0.id, displayName: $0.displayName) }
        } catch {
            throw ProviderErrorClassifier.classify(error).0
        }
    }

    // MARK: - Request construction

    private func buildRequest(for request: TranslationRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = firstByteTimeout

        let body = AnthropicRequestBodyBuilder.body(for: request, model: model)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Streaming

    private func runOneAttempt(urlRequest: URLRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws {
        try await runSSEStreamAttempt(
            urlRequest: urlRequest,
            firstByteTimeout: firstByteTimeout,
            totalTimeout: totalTimeout,
            completionPolicy: .requiresSentinel,
            lineParser: AnthropicSSELineParser(),
            parseErrorBody: Self.parseErrorBody,
            onEvent: onEvent
        )
    }

    private static func parseErrorBody(_ data: Data) -> (message: String?, code: String?) {
        struct ErrorBody: Decodable {
            struct Body: Decodable { let type: String; let message: String }
            let error: Body
        }
        guard let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return (String(data: data, encoding: .utf8), nil)
        }
        return (decoded.error.message, decoded.error.type)
    }
}

/// См. комментарий у одноимённого типа в `OpenAICompatibleProvider.swift` —
/// тот же приём, повторён здесь, а не расшарен, чтобы не создавать связность
/// между независимыми адаптерами ради одного `Bool`-флага.
private final class YieldedFlag: @unchecked Sendable {
    private(set) var value = false
    func markYielded() { value = true }
}
