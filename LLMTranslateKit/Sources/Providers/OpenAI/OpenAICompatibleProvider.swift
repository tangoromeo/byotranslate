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

    public func translate(request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
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
                        try await runOneAttempt(urlRequest: urlRequest) { text in
                            yieldedAny.markYielded()
                            continuation.yield(text)
                        }
                        continuation.finish()
                        return
                    } catch {
                        let (translationError, canRetry) = Self.classify(error)
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
        for try await _ in translate(request: request) {
            receivedAny = true
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
            struct ListResponse: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
            return decoded.data.map { ModelDescriptor(rawID: $0.id) }
        } catch {
            throw Self.classify(error).0
        }
    }

    // MARK: - Request construction

    private func buildRequest(for request: TranslationRequest) throws -> URLRequest {
        guard case let .text(text) = request.payload else {
            // Мультимодальные тела запросов — раздел 6.3 ТЗ, этап 3.
            throw TranslationError.modelDoesNotSupportImages
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = firstByteTimeout

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": request.maxOutputTokens,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Streaming

    private func runOneAttempt(urlRequest: URLRequest, onDelta: @escaping @Sendable (String) -> Void) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = firstByteTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        let delegate = OpenAISSEStreamDelegate(onDelta: onDelta)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.completion = { result in
                continuation.resume(with: result)
            }
            let task = session.dataTask(with: urlRequest)
            task.resume()
        }
    }

    // MARK: - Error classification

    /// Раздел 6.4, п. 5 ТЗ: один повтор на сетевую ошибку и на HTTP 429/5xx,
    /// на 401/403 — не повторять. Возвращает финальную `TranslationError`
    /// для UI и флаг «можно ли автоматически повторить прямо сейчас».
    static func classify(_ error: Error) -> (TranslationError, canRetry: Bool) {
        if let raw = error as? RawAttemptFailure {
            if raw.bodyCode == "insufficient_quota" {
                return (.insufficientQuota, false)
            }
            if let status = raw.httpStatus {
                switch status {
                case 401, 403: return (.authenticationRejected, false)
                case 402: return (.insufficientQuota, false)
                case 404: return (.modelUnavailable, false)
                case 429: return (.rateLimited, true)
                case 500...599:
                    return (.other(code: "\(status)", message: raw.bodyMessage ?? "server error"), true)
                default:
                    return (.other(code: "\(status)", message: raw.bodyMessage ?? "HTTP \(status)"), false)
                }
            }
            if raw.underlying != nil {
                return (.timeoutOrNoNetwork, true)
            }
            return (.other(code: nil, message: "unknown request failure"), false)
        }
        if let translationError = error as? TranslationError {
            // Уже финальная классифицированная ошибка (например, обрыв
            // потока или ошибка сервера в середине стрима) — не ретраим
            // автоматически второй раз поверх уже частично начатого ответа.
            return (translationError, false)
        }
        if error is URLError {
            return (.timeoutOrNoNetwork, true)
        }
        return (.other(code: nil, message: String(describing: error)), false)
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

/// Промежуточная ошибка одной HTTP-попытки — до финальной классификации в
/// `TranslationError`, чтобы retry-логика могла смотреть на сырой статус.
struct RawAttemptFailure: Error, Sendable {
    let httpStatus: Int?
    let underlying: Error?
    let bodyMessage: String?
    let bodyCode: String?
}

/// `URLSessionDataDelegate` вызывается последовательно на своей delegate
/// queue (по умолчанию — отдельная сериализованная `OperationQueue`), так
/// что мутируемое состояние здесь не требует блокировок.
private final class OpenAISSEStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onDelta: @Sendable (String) -> Void
    var completion: ((Result<Void, Error>) -> Void)?

    private var assembler = SSELineAssembler()
    private var sawDone = false
    private var httpStatus: Int?
    private var errorBody = Data()
    private var finished = false

    init(onDelta: @escaping @Sendable (String) -> Void) {
        self.onDelta = onDelta
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        httpStatus = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let status = httpStatus, !(200...299).contains(status) {
            errorBody.append(data)
            return
        }
        process(lines: assembler.feed(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }

        if let error {
            finish(.failure(RawAttemptFailure(httpStatus: httpStatus, underlying: error, bodyMessage: nil, bodyCode: nil)))
            return
        }
        if let status = httpStatus, !(200...299).contains(status) {
            let (message, code) = Self.parseErrorBody(errorBody)
            finish(.failure(RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: message, bodyCode: code)))
            return
        }
        if let leftover = assembler.finish() {
            process(lines: [leftover])
            if finished { return }
        }
        if sawDone {
            finish(.success(()))
        } else {
            finish(.failure(TranslationError.streamInterrupted))
        }
    }

    private func process(lines: [String]) {
        for line in lines {
            guard !finished else { return }
            do {
                guard let event = try OpenAIStreamLineParser.parse(line: line) else { continue }
                switch event {
                case let .contentDelta(text):
                    onDelta(text)
                case .done:
                    sawDone = true
                    finish(.success(()))
                case let .serverError(code, message):
                    finish(.failure(TranslationError.other(code: code, message: message)))
                }
            } catch {
                finish(.failure(TranslationError.other(code: nil, message: "malformed SSE line: \(line)")))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        completion?(result)
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
