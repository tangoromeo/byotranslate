import Foundation

/// Раздел 17 ТЗ v1.2 (локализация): `Text`/`NSLocalizedString` по умолчанию
/// ищут строки в `Bundle.main` — для кода внутри фреймворка это бандл
/// хоста (приложения или расширения), не самого `LLMTranslateKit.framework`,
/// где на самом деле лежит `Localizable.strings` этого модуля. Explicit
/// `bundle:`/`NSLocalizedString(bundle:)` с `Bundle.kit` — обязателен для
/// каждой локализуемой строки внутри Kit.
private final class KitBundleMarker {}

extension Bundle {
    public static let kit = Bundle(for: KitBundleMarker.self)
}
