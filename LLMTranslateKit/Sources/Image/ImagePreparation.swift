import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct PreparedImage: Sendable, Equatable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Раздел 10.7 ТЗ. Изображение никогда не попадает на диск — вся обработка
/// через `UIImage`/`Data` в памяти, ни один шаг не пишет во временную
/// директорию.
///
/// Собран только под `canImport(UIKit)`, поэтому недоступен для юнит-тестов
/// через кросс-платформенный SPM-харнесс (см. `README`/`NOTES` про Xcode
/// на этой сессии) — тестируется опосредованно через `ImageResizeMath` и
/// `ImageQualityLadder`, которые несут всю проверяемую логику отдельно от
/// реального кодирования.
public enum ImagePreparation {
    /// «Base64, ограничение полезной нагрузки 4 МБ» — раздел 10.7 ТЗ.
    /// Проверяется размер уже base64-закодированной строки, так как это и
    /// есть фактическая полезная нагрузка запроса.
    public static let maxPayloadBytes = 4 * 1024 * 1024
    /// Исходник остаётся PNG только если он и так PNG и меньше этого
    /// размера — раздел 10.7 ТЗ.
    public static let pngSourceSizeThreshold = 300 * 1024

    #if canImport(UIKit)
    public static func prepare(sourceData: Data) throws -> PreparedImage {
        guard let sourceImage = UIImage(data: sourceData) else {
            throw TranslationError.other(code: nil, message: "не удалось декодировать изображение")
        }
        let isSmallPNGSource = sourceData.isPNGSignature && sourceData.count < pngSourceSizeThreshold

        for step in ImageQualityLadder.steps {
            let target = ImageResizeMath.targetSize(
                originalWidth: sourceImage.size.width * sourceImage.scale,
                originalHeight: sourceImage.size.height * sourceImage.scale,
                maxLongSide: step.maxLongSide
            )
            guard let resized = Self.resize(sourceImage, to: target) else { continue }

            // PNG-путь пробуем только на первом (полноразмерном) шаге —
            // дальнейшие шаги ступенчатого понижения раздел 10.7 ТЗ
            // описывает уже в терминах JPEG-качества.
            if step.maxLongSide == ImageQualityLadder.defaultMaxLongSide,
               step.jpegQuality == ImageQualityLadder.steps[0].jpegQuality,
               isSmallPNGSource,
               let pngData = resized.pngData() {
                let base64Count = base64EncodedByteCount(for: pngData.count)
                if base64Count <= maxPayloadBytes {
                    return PreparedImage(data: pngData, mimeType: "image/png")
                }
            }

            guard let jpegData = resized.jpegData(compressionQuality: step.jpegQuality) else { continue }
            let base64Count = base64EncodedByteCount(for: jpegData.count)
            if base64Count <= maxPayloadBytes {
                return PreparedImage(data: jpegData, mimeType: "image/jpeg")
            }
        }
        throw TranslationError.imageTooLarge
    }

    private static func resize(_ image: UIImage, to size: (width: Int, height: Int)) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let targetSize = CGSize(width: size.width, height: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif

    /// Base64 кодирует каждые 3 байта в 4 символа, с паддингом до кратности 4.
    static func base64EncodedByteCount(for rawByteCount: Int) -> Int {
        ((rawByteCount + 2) / 3) * 4
    }
}

extension Data {
    /// Первые 8 байт PNG-сигнатуры (89 50 4E 47 0D 0A 1A 0A).
    var isPNGSignature: Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard count >= signature.count else { return false }
        return prefix(signature.count).elementsEqual(signature)
    }
}
