import Foundation

/// Раздел 6.1 ТЗ v1.2: один и тот же стриминговый конвейер для всех трёх
/// провайдеров. У каждого — свой формат строки и своё завершение стрима
/// (OpenAI — строка `[DONE]`, Anthropic — событие `message_stop`, Gemini —
/// просто закрытие соединения без терминатора), поэтому эти два места
/// параметризуются, остальное (byte-buffering, ошибки, ретраи) — общее.
public enum SSELineEvent: Sendable, Equatable {
    case delta(String)
    case usage(promptTokens: Int?, completionTokens: Int?)
    /// Явный терминатор потока конкретного провайдера (не все его имеют).
    case streamDone
    case serverError(code: String?, message: String)
}

public enum SSEStreamCompletionPolicy: Sendable, Equatable {
    /// Успех только если пришёл явный терминатор — OpenAI (`[DONE]`),
    /// Anthropic (`message_stop`).
    case requiresSentinel
    /// Успех — само закрытие соединения после HTTP 200, терминатора нет —
    /// Gemini.
    case closeIsSuccess
}

public protocol SSEProviderLineParser: Sendable {
    func parse(line: String) throws -> SSELineEvent?
}

/// Промежуточная ошибка одной HTTP-попытки — до финальной классификации в
/// `TranslationError`, чтобы retry-логика могла смотреть на сырой статус.
/// `bodyCode` — общий канал для «эквивалента insufficient_quota» у любого
/// провайдера: каждый адаптер сам решает, при каком условии в своём формате
/// ошибки подставить сюда именно эту строку, чтобы получить общую
/// обработку в `ProviderErrorClassifier` бесплатно.
public struct RawAttemptFailure: Error, Sendable {
    public let httpStatus: Int?
    public let underlying: Error?
    public let bodyMessage: String?
    public let bodyCode: String?

    public init(httpStatus: Int?, underlying: Error?, bodyMessage: String?, bodyCode: String?) {
        self.httpStatus = httpStatus
        self.underlying = underlying
        self.bodyMessage = bodyMessage
        self.bodyCode = bodyCode
    }
}

/// Раздел 6.4, п. 6 ТЗ: один повтор на сетевую ошибку и на HTTP 429/5xx, на
/// 401/403 — не повторять. Общая для всех провайдеров — раздел 6.1 ТЗ v1.2.
public enum ProviderErrorClassifier {
    public static func classify(_ error: Error) -> (TranslationError, canRetry: Bool) {
        if let raw = error as? RawAttemptFailure {
            if raw.bodyCode == "insufficient_quota" {
                return (.insufficientQuota, false)
            }
            // Реальная сетевая ошибка важнее захваченного HTTP-статуса —
            // см. подробный разбор в комментарии у места обнаружения бага
            // (git-история `OpenAICompatibleProvider.classify`).
            if raw.underlying != nil {
                return (.timeoutOrNoNetwork, true)
            }
            if let status = raw.httpStatus, !(200...299).contains(status) {
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

/// Одна сетевая попытка потокового запроса — общая для всех адаптеров.
public func runSSEStreamAttempt(
    urlRequest: URLRequest,
    firstByteTimeout: TimeInterval,
    totalTimeout: TimeInterval,
    completionPolicy: SSEStreamCompletionPolicy,
    lineParser: SSEProviderLineParser,
    parseErrorBody: @escaping @Sendable (Data) -> (message: String?, code: String?),
    onEvent: @escaping @Sendable (StreamEvent) -> Void
) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = firstByteTimeout
    configuration.timeoutIntervalForResource = totalTimeout
    let delegate = SharedSSEStreamDelegate(
        completionPolicy: completionPolicy,
        lineParser: lineParser,
        parseErrorBody: parseErrorBody,
        onEvent: onEvent
    )
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

/// `onDelta`/`onEvent` вызываются последовательно с delegate queue одной
/// сетевой попытки — конкурентного доступа нет, но `@Sendable`-замыкания
/// этого не знают статически.
private final class SharedSSEStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let completionPolicy: SSEStreamCompletionPolicy
    private let lineParser: SSEProviderLineParser
    private let parseErrorBody: @Sendable (Data) -> (message: String?, code: String?)
    private let onEvent: @Sendable (StreamEvent) -> Void
    var completion: ((Result<Void, Error>) -> Void)?

    private var assembler = SSELineAssembler()
    private var sawSentinel = false
    private var httpStatus: Int?
    private var errorBody = Data()
    private var finished = false

    init(
        completionPolicy: SSEStreamCompletionPolicy,
        lineParser: SSEProviderLineParser,
        parseErrorBody: @escaping @Sendable (Data) -> (message: String?, code: String?),
        onEvent: @escaping @Sendable (StreamEvent) -> Void
    ) {
        self.completionPolicy = completionPolicy
        self.lineParser = lineParser
        self.parseErrorBody = parseErrorBody
        self.onEvent = onEvent
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
            let (message, code) = parseErrorBody(errorBody)
            finish(.failure(RawAttemptFailure(httpStatus: status, underlying: nil, bodyMessage: message, bodyCode: code)))
            return
        }
        if let leftover = assembler.finish() {
            process(lines: [leftover])
            if finished { return }
        }
        switch completionPolicy {
        case .requiresSentinel:
            if sawSentinel {
                finish(.success(()))
            } else {
                finish(.failure(TranslationError.streamInterrupted))
            }
        case .closeIsSuccess:
            finish(.success(()))
        }
    }

    private func process(lines: [String]) {
        for line in lines {
            guard !finished else { return }
            do {
                guard let event = try lineParser.parse(line: line) else { continue }
                switch event {
                case let .delta(text):
                    onEvent(.delta(text))
                case let .usage(promptTokens, completionTokens):
                    onEvent(.usage(promptTokens: promptTokens, completionTokens: completionTokens))
                case .streamDone:
                    sawSentinel = true
                    if completionPolicy == .requiresSentinel {
                        finish(.success(()))
                    }
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
}
