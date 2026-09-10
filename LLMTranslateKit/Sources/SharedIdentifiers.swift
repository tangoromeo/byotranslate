import Foundation

/// Общие для всех таргетов идентификаторы App Group / Keychain access group
/// (раздел 5 ТЗ). Значения должны дословно совпадать с `project.yml`.
public enum SharedIdentifiers {
    public static let appGroup = "group.com.tyrex.llmtranslate"

    /// `$(AppIdentifierPrefix)` подставляется системой при подписи — здесь
    /// достаточно суффикса, реальное значение читается из entitlements
    /// таргета, не из этой константы напрямую.
    public static let keychainAccessGroupSuffix = "com.tyrex.llmtranslate.shared"
}
