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
    /// Раздел 10.7 ТЗ: не влезло даже после ступенчатого понижения
    /// качества/разрешения.
    case imageTooLarge
    /// Раздел 10.4/11 ТЗ: E2/E3 — доступ к «Фото» не выдан.
    case noPhotoAccess
    /// Раздел 10.4/11 ТЗ: в смарт-альбоме «Снимки экрана» нет ни одного элемента.
    case noScreenshotsFound
    case other(code: String?, message: String)

    /// `String` (не `LocalizedStringKey`) — автолокализация `Text` по
    /// литералу здесь не работает, нужен явный `NSLocalizedString` с
    /// `bundle: .kit` (код исполняется внутри фреймворка, `Bundle.main` был
    /// бы бандлом хоста, не Kit).
    public var localizedUserMessage: String {
        switch self {
        case .missingAPIKey: NSLocalizedString("Не задан API-ключ", bundle: .kit, comment: "")
        case .authenticationRejected: NSLocalizedString("Ключ отклонён провайдером", bundle: .kit, comment: "")
        case .rateLimited: NSLocalizedString("Лимит запросов. Попробуйте через минуту", bundle: .kit, comment: "")
        case .insufficientQuota: NSLocalizedString("Закончился баланс у провайдера", bundle: .kit, comment: "")
        case .modelUnavailable: NSLocalizedString("Модель недоступна для этого ключа", bundle: .kit, comment: "")
        case .modelDoesNotSupportImages: NSLocalizedString("Выбранная модель не понимает изображения", bundle: .kit, comment: "")
        case .streamInterrupted, .timeoutOrNoNetwork: NSLocalizedString("Нет ответа от провайдера", bundle: .kit, comment: "")
        case .emptyResponse: NSLocalizedString("Модель вернула пустой ответ", bundle: .kit, comment: "")
        case .imageTooLarge: NSLocalizedString("Изображение слишком большое", bundle: .kit, comment: "")
        case .noPhotoAccess: NSLocalizedString("Нет доступа к медиатеке", bundle: .kit, comment: "")
        case .noScreenshotsFound: NSLocalizedString("Не нашёл ни одного снимка экрана", bundle: .kit, comment: "")
        case .other: NSLocalizedString("Ошибка перевода", bundle: .kit, comment: "")
        }
    }

    /// Раздел 11 ТЗ: «Ретрай»/«Повторить» доступно не для всех ошибок —
    /// на 401/403 не повторять, сразу в ошибку аутентификации.
    public var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .authenticationRejected, .insufficientQuota,
             .modelUnavailable, .modelDoesNotSupportImages, .imageTooLarge,
             .noPhotoAccess, .noScreenshotsFound:
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

    /// Раздел 13.5 ТЗ: статус для лога последних запросов — только тег
    /// случая, никогда текст ошибки провайдера (в нём мог бы просочиться
    /// фрагмент исходного текста).
    public var logTag: String {
        switch self {
        case .missingAPIKey: "missingAPIKey"
        case .authenticationRejected: "authenticationRejected"
        case .rateLimited: "rateLimited"
        case .insufficientQuota: "insufficientQuota"
        case .modelUnavailable: "modelUnavailable"
        case .modelDoesNotSupportImages: "modelDoesNotSupportImages"
        case .streamInterrupted: "streamInterrupted"
        case .timeoutOrNoNetwork: "timeoutOrNoNetwork"
        case .emptyResponse: "emptyResponse"
        case .imageTooLarge: "imageTooLarge"
        case .noPhotoAccess: "noPhotoAccess"
        case .noScreenshotsFound: "noScreenshotsFound"
        case let .other(code, _): "other" + (code.map { "(\($0))" } ?? "")
        }
    }
}
