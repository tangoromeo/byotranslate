import Foundation

/// Одна запись рейтинга «лучше» (см. `bench/RESULTS.md`, `docs/RATINGS.md`).
public struct ModelRating: Sendable, Equatable {
    /// Нормализованный ключ (`ModelRatings.key(for:)`).
    public let key: String
    /// Идентификатор в OpenRouter, на котором мерили.
    public let name: String
    /// Взвешенный рейтинг 0...100 (качество, цена, скорость), выше — лучше.
    public let score: Int
    /// Рейтинг с упором на качество перевода 0...100: для сильной модели
    /// («Точнее»), где цена и скорость важны меньше.
    public let qualityScore: Int
    /// Сколько предложений в самом маленьком замере: до 50 числу верить меньше.
    public let sentences: Int
    /// Замер показал: без отключения размышления модель с лимитом ответа
    /// приложения отдаёт пустые ответы.
    public let disableReasoningRecommended: Bool

    public init(
        key: String,
        name: String,
        score: Int,
        qualityScore: Int? = nil,
        sentences: Int,
        disableReasoningRecommended: Bool = false
    ) {
        self.key = key
        self.name = name
        self.score = score
        self.qualityScore = qualityScore ?? score
        self.sentences = sentences
        self.disableReasoningRecommended = disableReasoningRecommended
    }
}

/// Какой из двух рейтингов использовать.
public enum RatingKind: Sendable {
    /// Взвешенный: качество, цена, скорость. Для рабочей модели.
    case balanced
    /// С упором на качество перевода. Для сильной модели.
    case quality
}

extension ModelRating {
    public func score(for kind: RatingKind) -> Int {
        kind == .balanced ? score : qualityScore
    }
}

/// Рейтинги моделей: взвешенный («лучше») и с упором на качество
/// (веса и формулы — `bench/bench.py rank`). Данные генерируются скриптом в
/// `ModelRatingsData.swift` и обновляются вместе с релизом приложения:
/// удалённого конфига нет (раздел 14 ТЗ — единственный сетевой адресат это
/// endpoint пользователя).
public enum ModelRatings {
    /// Через сколько дней после замера рейтинг считается устаревшим и в
    /// интерфейсе появляется подсказка. Пересматривать — по `docs/RATINGS.md`.
    public static let staleAfterDays = 120
    /// Умолчания мастера берутся только из моделей, измеренных не менее чем на
    /// стольких предложениях: на меньшей выборке отставание — в основном шум.
    public static let minSentencesForDefaults = 50

    // MARK: - Ключ модели

    private static let ignoredSuffixes: Set<String> = ["free", "batch", "nitro", "floor", "extended", "online"]

    /// Один и тот же ключ для «google/gemini-2.5-flash-lite» (OpenRouter),
    /// «models/gemini-2.5-flash-lite» (Gemini) и «gemini-2.5-flash-lite»:
    /// без компании, с точками вместо дефисов, без суффикса-даты и вариантов
    /// `:free`/`:batch`. «claude-haiku-4-5-20251001» и «anthropic/claude-haiku-4.5»
    /// получают один ключ.
    public static func key(for rawID: String) -> String {
        var id = rawID.lowercased()
        if let colon = id.lastIndex(of: ":"), ignoredSuffixes.contains(String(id[id.index(after: colon)...])) {
            id = String(id[..<colon])
        }
        if let slash = id.lastIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
        }
        id = id.replacingOccurrences(of: ".", with: "-")
        for pattern in ["-20\\d{6}$", "-20\\d{2}-\\d{2}-\\d{2}$"] {
            id = id.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return id
    }

    // MARK: - Поиск и сортировка

    public static func rating(for rawID: String, in ratings: [ModelRating] = entries) -> ModelRating? {
        let wanted = key(for: rawID)
        return ratings.first { $0.key == wanted }
    }

    /// Сначала модели с рейтингом по убыванию балла выбранного рейтинга, потом
    /// остальные по алфавиту: неоценённая модель не «хуже», а просто не измерена.
    public static func sorted(
        _ models: [ModelDescriptor],
        by kind: RatingKind = .balanced,
        ratings: [ModelRating] = entries
    ) -> [ModelDescriptor] {
        let scored = models.map { ($0, rating(for: $0.rawID, in: ratings)) }
        let rated = scored.compactMap { model, rating in rating.map { (model, $0) } }
            .sorted { lhs, rhs in
                let (left, right) = (lhs.1.score(for: kind), rhs.1.score(for: kind))
                return left != right ? left > right : lhs.0.rawID < rhs.0.rawID
            }
            .map(\.0)
        let unrated = scored.filter { $0.1 == nil }.map(\.0)
            .sorted { $0.rawID.localizedCaseInsensitiveCompare($1.rawID) == .orderedAscending }
        return rated + unrated
    }

    /// Умолчания для нового подключения. Рабочая — лучшая по взвешенному
    /// рейтингу. Сильная — лучшая по качеству среди остальных, но только если по
    /// качеству она не слабее рабочей: «Точнее» на модели, которая по замеру
    /// хуже, бессмысленно. Модели, про которые известно, что они не читают
    /// изображения, пропускаются (рабочий слот получает и скриншоты); модели с
    /// малой выборкой замера не подставляются. Нет подходящих — `nil`, выбор за
    /// пользователем.
    public static func defaults(
        from models: [ModelDescriptor],
        ratings: [ModelRating] = entries
    ) -> (working: ModelDescriptor?, strong: ModelDescriptor?) {
        func eligible(_ model: ModelDescriptor) -> Bool {
            guard model.supportsImages != false,
                  let rating = rating(for: model.rawID, in: ratings)
            else { return false }
            return rating.sentences >= minSentencesForDefaults
        }
        let working = sorted(models, by: .balanced, ratings: ratings).first(where: eligible)
        guard let working else { return (nil, nil) }
        let workingQuality = rating(for: working.rawID, in: ratings)?.qualityScore ?? 0
        let strong = sorted(models, by: .quality, ratings: ratings).first { candidate in
            candidate.rawID != working.rawID && eligible(candidate)
        }
        guard let strong, let strongRating = rating(for: strong.rawID, in: ratings),
              strongRating.qualityScore >= workingQuality
        else { return (working, nil) }
        return (working, strong)
    }

    // MARK: - Свежесть данных

    public static var measuredDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: measuredAt)
    }

    public static func isStale(now: Date = Date(), measured: Date? = measuredDate) -> Bool {
        guard let measured else { return true }
        return now.timeIntervalSince(measured) > Double(staleAfterDays) * 86_400
    }
}
