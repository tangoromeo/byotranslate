import Foundation

/// Раздел 9 ТЗ v1.2 (строка 410): «RTL-раскладка (иврит и арабский —
/// целевые языки, текст должен выравниваться по правому краю при
/// RTL-результате)». Узкое требование — выравнивание блока перевода, не
/// разворот интерфейса приложения (`layoutDirection`).
public enum TextDirectionResolver {
    public static func isRightToLeft(_ language: Locale.Language) -> Bool {
        language.characterDirection == .rightToLeft
    }
}
