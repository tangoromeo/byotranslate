import Foundation

/// Раздел 6.2/6.4 ТЗ. `baseURL` настраиваемый — даёт поддержку OpenRouter,
/// Groq, DeepSeek, Azure OpenAI, корпоративных прокси и локального
/// Ollama/LM Studio без единой строки нового кода.
public final class OpenAICompatibleProvider: TranslationProvider, @unchecked Sendable {
    public let id: ProviderID = .openAICompatible

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let firstByteTimeout: TimeInterval
    private let totalTimeout: TimeInterval

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        firstByteTimeout: TimeInterval = 8,
        totalTimeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.firstByteTimeout = firstByteTimeout
        self.totalTimeout = totalTimeout
    }

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

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
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode
                throw RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: nil, bodyCode: nil)
            }
            return try OpenAIModelListParsing.parse(data)
        } catch {
            throw ProviderErrorClassifier.classify(error).0
        }
    }

    // MARK: - Request construction

    private func buildRequest(for request: TranslationRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = firstByteTimeout

        let body = OpenAIRequestBodyBuilder.body(for: request, model: model, baseURL: baseURL)
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
            lineParser: OpenAISSELineParser(),
            parseErrorBody: Self.parseErrorBody,
            onEvent: onEvent
        )
    }

    private static func parseErrorBody(_ data: Data) -> (message: String?, code: String?) {
        struct ErrorBody: Decodable {
            struct Body: Decodable { let message: String; let code: String? }
            let error: Body
        }
        guard let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return (String(data: data, encoding: .utf8), nil)
        }
        return (decoded.error.message, decoded.error.code)
    }
}

/// `onDelta` вызывается последовательно с delegate queue одной сетевой
/// попытки, а читается уже после того, как `runOneAttempt` вернула
/// управление (успешно или с ошибкой) — конкурентного доступа в реальности
/// нет, но `@Sendable`-замыкание этого не знает статически.
private final class YieldedFlag: @unchecked Sendable {
    private(set) var value = false
    func markYielded() { value = true }
}

/// Адаптер `OpenAIStreamLineParser` (раздел 6.2 ТЗ) под общий протокол
/// `SSEProviderLineParser` из `Providers/Shared/SSEStreamRunner.swift`.
private struct OpenAISSELineParser: SSEProviderLineParser {
    func parse(line: String) throws -> SSELineEvent? {
        guard let event = try OpenAIStreamLineParser.parse(line: line) else { return nil }
        switch event {
        case let .contentDelta(text): return .delta(text)
        case .done: return .streamDone
        case let .serverError(code, message): return .serverError(code: code, message: message)
        }
    }
}
