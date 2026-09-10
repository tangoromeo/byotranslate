import Foundation

/// Маппинг ошибок — раздел 11 ТЗ. Никаких сырых сообщений от API в UI:
/// `localizedUserMessage` — то, что видит пользователь, `details` — то, что
/// уходит в раскрывающуюся секцию «Подробности».
public enum TranslationError: Error, Sendable, Equatable {
    case missingAPIKey
    case authenticationRejected
    case rateLimited
    case insufficientQuota
    case modelUnavailable
    case modelDoesNotSupportImages
    /// Поток оборвался, не дойдя до терминатора (`[DONE]` и т. п.).
    case streamInterrupted
    case timeoutOrNoNetwork
    case emptyResponse
    case other(code: String?, message: String)

    public var localizedUserMessage: String {
        switch self {
        case .missingAPIKey: "Не задан API-ключ"
        case .authenticationRejected: "Ключ отклонён провайдером"
        case .rateLimited: "Лимит запросов. Попробуйте через минуту"
        case .insufficientQuota: "Закончился баланс у провайдера"
        case .modelUnavailable: "Модель недоступна для этого ключа"
        case .modelDoesNotSupportImages: "Выбранная модель не понимает изображения"
        case .streamInterrupted, .timeoutOrNoNetwork: "Нет ответа от провайдера"
        case .emptyResponse: "Модель вернула пустой ответ"
        case .other: "Ошибка перевода"
        }
    }

    /// Раздел 11 ТЗ: «Ретрай»/«Повторить» доступно не для всех ошибок —
    /// на 401/403 не повторять, сразу в ошибку аутентификации.
    public var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .authenticationRejected, .insufficientQuota,
             .modelUnavailable, .modelDoesNotSupportImages:
            false
        case .rateLimited, .streamInterrupted, .timeoutOrNoNetwork, .emptyResponse, .other:
            true
        }
    }

    /// Полный текст ошибки провайдера — для секции «Подробности» (раздел 11 ТЗ).
    public var details: String? {
        if case let .other(code, message) = self {
            return code.map { "\($0): \(message)" } ?? message
        }
        return nil
    }
}
