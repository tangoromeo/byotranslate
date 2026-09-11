import Foundation

/// Раздел 6.2/6.4 ТЗ v1.2, этап 2. `baseURL` настраиваемый, как у остальных
/// двух адаптеров. **Важно**: `?alt=sse` в URL обязателен — без него
/// `streamGenerateContent` отдаёт один JSON-массив, не построчный SSE (это
/// расхождение с таблицей ТЗ, обнаружено и зафиксировано при реализации).
public final class GeminiProvider: TranslationProvider, @unchecked Sendable {
    public let id: ProviderID = .googleGemini

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

    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

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
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode
                throw RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: nil, bodyCode: nil)
            }
            struct ListResponse: Decodable {
                struct Model: Decodable { let name: String; let displayName: String? }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
            return decoded.models.map {
                // `name` приходит как "models/gemini-2.5-flash" — префикс не
                // часть идентификатора модели, который идёт в URL запроса.
                let rawID = $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name
                return ModelDescriptor(rawID: rawID, displayName: $0.displayName)
            }
        } catch {
            throw ProviderErrorClassifier.classify(error).0
        }
    }

    // MARK: - Request construction

    private func buildRequest(for request: TranslationRequest) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("models/\(model):streamGenerateContent"),
            resolvingAgainstBaseURL: false
        ) else {
            throw TranslationError.other(code: nil, message: "invalid Gemini URL")
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else {
            throw TranslationError.other(code: nil, message: "invalid Gemini URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = firstByteTimeout

        let body = GeminiRequestBodyBuilder.body(for: request)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Streaming

    private func runOneAttempt(urlRequest: URLRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws {
        try await runSSEStreamAttempt(
            urlRequest: urlRequest,
            firstByteTimeout: firstByteTimeout,
            totalTimeout: totalTimeout,
            completionPolicy: .closeIsSuccess,
            lineParser: GeminiSSELineParser(),
            parseErrorBody: Self.parseErrorBody,
            onEvent: onEvent
        )
    }

    private static func parseErrorBody(_ data: Data) -> (message: String?, code: String?) {
        struct ErrorBody: Decodable {
            struct Body: Decodable { let message: String; let status: String? }
            let error: Body
        }
        guard let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return (String(data: data, encoding: .utf8), nil)
        }
        return (decoded.error.message, decoded.error.status)
    }
}

/// См. комментарий у одноимённого типа в `OpenAICompatibleProvider.swift`.
private final class YieldedFlag: @unchecked Sendable {
    private(set) var value = false
    func markYielded() { value = true }
}
