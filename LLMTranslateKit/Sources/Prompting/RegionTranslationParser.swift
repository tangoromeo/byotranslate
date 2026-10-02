import Foundation

/// Раздел B6, этап 3: разбор ответа модели на лист фрагментов. Просим JSON
/// `[{"n":1,"t":"…"}]`, но модели охотно оборачивают его в текст, меняют
/// имена ключей или отвечают списком «1. …» — разбираем всё это, а не
/// падаем на первом же отклонении.
public enum RegionTranslationParser {
    /// Номер фрагмента на листе (с 1) → перевод. Пустые переводы отбрасываются.
    public static func parse(_ response: String) -> [Int: String] {
        if let json = parseJSON(response), !json.isEmpty { return json }
        return parseLines(response)
    }

    private static let numberKeys = ["n", "id", "number", "index", "no"]
    private static let textKeys = ["t", "text", "translation", "tr"]

    private static func parseJSON(_ response: String) -> [Int: String]? {
        guard let start = response.firstIndex(where: { $0 == "[" || $0 == "{" }),
              let end = response.lastIndex(where: { $0 == "]" || $0 == "}" }),
              start < end,
              let data = String(response[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        var result: [Int: String] = [:]
        func add(_ number: Int?, _ text: String?) {
            guard let number, let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result[number] = trimmed }
        }

        if let array = object as? [[String: Any]] {
            for item in array {
                add(
                    numberKeys.lazy.compactMap { toInt(item[$0]) }.first,
                    textKeys.lazy.compactMap { item[$0] as? String }.first
                )
            }
        } else if let dictionary = object as? [String: Any] {
            if let nested = dictionary.values.first(where: { $0 is [[String: Any]] }) as? [[String: Any]] {
                return parseJSON(String(decoding: (try? JSONSerialization.data(withJSONObject: nested)) ?? Data(), as: UTF8.self))
            }
            for (key, value) in dictionary { add(Int(key), value as? String) }
        } else if let array = object as? [String] {
            // «Просто массив строк» — по порядку, с 1.
            for (offset, text) in array.enumerated() { add(offset + 1, text) }
        }
        return result
    }

    private static func toInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func parseLines(_ response: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(where: { !$0.isNumber }),
                  separator > trimmed.startIndex,
                  let number = Int(trimmed[trimmed.startIndex..<separator])
            else { continue }
            let rest = trimmed[separator...]
                .drop(while: { ".:)-–— \t".contains($0) })
                .trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { result[number] = rest }
        }
        return result
    }
}
