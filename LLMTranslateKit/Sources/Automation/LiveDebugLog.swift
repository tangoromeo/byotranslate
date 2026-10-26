import Foundation

/// Временный журнал спайка B8 (только текст событий, без содержимого экрана):
/// общий для расширения трансляции и приложения файл в App Group, его забирает
/// `devicectl`. Файл собирается и в Kit, и напрямую в расширение (Kit там не
/// линкуется). Убрать в M4.
public enum LiveDebugLog {
    public static func write(_ line: String) {
        let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroup)
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedIdentifiers.appGroup)?
            .appendingPathComponent("live-debug.log") else {
            defaults?.set("containerURL == nil", forKey: "liveDebugError")
            return
        }
        defaults?.set(Date().timeIntervalSince1970, forKey: "liveDebugLastCall")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            do { try data.write(to: url) } catch { defaults?.set(String(describing: error), forKey: "liveDebugError") }
        }
    }

    /// Последние строки журнала — для показа на экране «Живой режим».
    public static func tail(_ count: Int = 30) -> String {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedIdentifiers.appGroup)?
            .appendingPathComponent("live-debug.log"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "(журнал пуст или недоступен)" }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }
}
