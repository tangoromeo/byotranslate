import CoreGraphics

/// Строка состояния (часы, батарея, сеть) на полноэкранном скриншоте телефона:
/// переводить её незачем, а часы меняются каждую минуту — каждый раз новый
/// отпечаток и лишний запрос к модели в обход кэша.
public enum StatusBarFilter {
    /// Доля высоты снимка, которую занимает строка состояния (с запасом:
    /// 54 pt на iPhone с Dynamic Island ≈ 5,8% при высоте 932 pt).
    static let stripFraction: CGFloat = 0.065

    /// Похоже ли изображение на полноэкранный скриншот iPhone в портрете
    /// (высота/ширина ≈ 2,0–2,25). Фото и обрезанные картинки не трогаем.
    public static func isFullScreenPhoneScreenshot(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > size.width else { return false }
        let aspect = size.height / size.width
        return (2.0...2.25).contains(aspect)
    }

    /// Области без тех, что целиком лежат в полосе строки состояния.
    public static func removingStatusBar(_ regions: [TextRegion], imageSize: CGSize) -> [TextRegion] {
        guard isFullScreenPhoneScreenshot(imageSize) else { return regions }
        return regions.filter { $0.rect.maxY > stripFraction }
    }
}
