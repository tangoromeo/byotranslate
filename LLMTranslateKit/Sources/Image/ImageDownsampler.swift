import CoreGraphics
import Foundation
import ImageIO

/// Чтение изображения сразу в уменьшенном размере, без полной распаковки.
/// `UIImage(data:)` на фото в 12 Мп держит в памяти ~48 МБ растра (и это
/// повторялось на каждый показ/кроп/подготовку); у расширения «Поделиться»
/// лимит памяти на весь процесс небольшой, и такое фото его убивало.
/// ImageIO декодирует JPEG/HEIC прямо в нужный размер.
public enum ImageDownsampler {
    /// Ориентация из EXIF уже применена; изображение никогда не увеличивается.
    public static func cgImage(from data: Data, maxLongSide: CGFloat) -> CGImage? {
        guard maxLongSide > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let longSide = pixelLongSide(of: source) ?? maxLongSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxLongSide, longSide),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Длинная сторона исходного изображения в пикселях, без декодирования.
    public static func pixelLongSide(of data: Data) -> CGFloat? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(pixelLongSide(of:))
    }

    private static func pixelLongSide(of source: CGImageSource) -> CGFloat? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return max(width, height)
    }
}

#if canImport(UIKit)
import UIKit

extension ImageDownsampler {
    public static func uiImage(from data: Data, maxLongSide: CGFloat) -> UIImage? {
        cgImage(from: data, maxLongSide: maxLongSide).map { UIImage(cgImage: $0) }
    }
}
#endif
