import XCTest
@testable import LLMTranslateKit

/// Рейтинг моделей: ключи, сортировка, умолчания, свежесть данных.
final class ModelRatingsTests: XCTestCase {
    /// Та же таблица, что `ModelKeyTests.TABLE` в bench/test_bench.py: ключи Python
    /// (генерирует данные) и Swift (ищет по ним) обязаны совпадать.
    func test_key_parity_with_python_table() {
        let table: [String: String] = [
            "google/gemini-2.5-flash-lite": "gemini-2-5-flash-lite",
            "models/gemini-2.5-flash-lite": "gemini-2-5-flash-lite",
            "gemini-2.5-flash-lite": "gemini-2-5-flash-lite",
            "anthropic/claude-haiku-4.5": "claude-haiku-4-5",
            "claude-haiku-4-5-20251001": "claude-haiku-4-5",
            "gpt-4.1-mini-2025-04-14": "gpt-4-1-mini",
            "openai/gpt-4.1-mini": "gpt-4-1-mini",
            "qwen/qwen3.5-plus-20260420": "qwen3-5-plus",
            "deepseek/deepseek-v3.2": "deepseek-v3-2",
            "google/gemini-2.5-flash-lite:batch": "gemini-2-5-flash-lite",
            "x/some-model:thinking": "some-model:thinking",
            "GPT-4.1": "gpt-4-1",
        ]
        for (raw, expected) in table {
            XCTAssertEqual(ModelRatings.key(for: raw), expected, raw)
        }
    }

    func test_sameModel_viaDifferentProviders_getsTheSameRating() {
        let openRouter = ModelRatings.rating(for: "google/gemini-2.5-flash-lite")
        XCTAssertNotNil(openRouter)
        XCTAssertEqual(openRouter, ModelRatings.rating(for: "gemini-2.5-flash-lite"))
        XCTAssertEqual(ModelRatings.rating(for: "claude-haiku-4-5-20251001")?.name, "anthropic/claude-haiku-4.5")
    }

    func test_unmeasuredModel_hasNoRating() {
        XCTAssertNil(ModelRatings.rating(for: "acme/never-measured-1"))
    }

    // MARK: - Сортировка и умолчания (на своих данных, а не на сгенерированных)

    /// score — взвешенный, q — с упором на качество.
    private let ratings = [
        ModelRating(key: "a", name: "v/a", score: 90, qualityScore: 60, sentences: 100),
        ModelRating(key: "b", name: "v/b", score: 70, qualityScore: 95, sentences: 100),
        ModelRating(key: "c", name: "v/c", score: 70, qualityScore: 80, sentences: 100),
        ModelRating(key: "d", name: "v/d", score: 50, qualityScore: 40, sentences: 100),
        ModelRating(key: "tiny", name: "v/tiny", score: 99, qualityScore: 99, sentences: 20),
    ]

    private func descriptor(_ id: String, images: Bool? = nil) -> ModelDescriptor {
        ModelDescriptor(rawID: id, supportsImages: images)
    }

    func test_sorted_balanced_ratedFirstByScore_thenUnratedAlphabetically() {
        let models = ["v/zzz", "v/d", "v/b", "v/aaa", "v/a", "v/c"].map { descriptor($0) }
        let order = ModelRatings.sorted(models, by: .balanced, ratings: ratings).map(\.rawID)
        XCTAssertEqual(order, ["v/a", "v/b", "v/c", "v/d", "v/aaa", "v/zzz"])
    }

    func test_sorted_quality_usesTheOtherScore() {
        let models = ["v/a", "v/b", "v/c", "v/d"].map { descriptor($0) }
        XCTAssertEqual(ModelRatings.sorted(models, by: .quality, ratings: ratings).map(\.rawID), ["v/b", "v/c", "v/a", "v/d"])
    }

    func test_sorted_tieBrokenByIdDeterministically() {
        let models = [descriptor("v/c"), descriptor("v/b")]
        XCTAssertEqual(ModelRatings.sorted(models, by: .balanced, ratings: ratings).map(\.rawID), ["v/b", "v/c"])
    }

    func test_sorted_doesNotLoseOrDuplicateModels() {
        let models = (0..<20).map { descriptor("v/m\($0)") } + [descriptor("v/a")]
        for kind in [RatingKind.balanced, .quality] {
            XCTAssertEqual(ModelRatings.sorted(models, by: kind, ratings: ratings).count, models.count)
        }
    }

    func test_qualityScore_defaultsToScore_whenNotGiven() {
        XCTAssertEqual(ModelRating(key: "x", name: "x", score: 42, sentences: 100).qualityScore, 42)
    }

    func test_defaults_workingIsBestBalanced_strongIsBestQualityAmongOthers() {
        let models = ["v/d", "v/a", "v/b", "v/x"].map { descriptor($0) }
        let result = ModelRatings.defaults(from: models, ratings: ratings)
        XCTAssertEqual(result.working?.rawID, "v/a")   // взвешенный: 90
        XCTAssertEqual(result.strong?.rawID, "v/b")    // качество: 95, выше, чем у рабочей (60)
    }

    func test_defaults_strongIsNeverWeakerInQualityThanWorking() {
        // рабочая v/b — лучшая и по качеству (95): сильнее неё никого нет
        let only = [ModelRating(key: "b", name: "v/b", score: 90, qualityScore: 95, sentences: 100),
                    ModelRating(key: "e", name: "v/e", score: 60, qualityScore: 50, sentences: 100)]
        let models = [descriptor("v/b"), descriptor("v/e")]
        let result = ModelRatings.defaults(from: models, ratings: only)
        XCTAssertEqual(result.working?.rawID, "v/b")
        XCTAssertNil(result.strong, "«Точнее» на модели, которая по замеру слабее, не предлагаем")
    }

    func test_defaults_skipTinySamples() {
        let models = [descriptor("v/tiny"), descriptor("v/a"), descriptor("v/b")]
        let result = ModelRatings.defaults(from: models, ratings: ratings)
        XCTAssertEqual(result.working?.rawID, "v/a")
        XCTAssertNotEqual(result.strong?.rawID, "v/tiny")
    }

    func test_defaults_skipModelsKnownNotToReadImages() {
        // v/a — лучшая по взвешенному, но не читает изображения: рабочей не станет
        let models = [descriptor("v/a", images: false), descriptor("v/b", images: true), descriptor("v/c", images: nil)]
        let result = ModelRatings.defaults(from: models, ratings: ratings)
        XCTAssertEqual(result.working?.rawID, "v/b")
        // v/c по качеству (80) слабее рабочей v/b (95) — «Точнее» на ней не предлагаем
        XCTAssertNil(result.strong)
        // и сама v/a не может быть сильной, пока известно, что она не читает изображения
        let withA = ModelRatings.defaults(from: [descriptor("v/a", images: false), descriptor("v/d", images: true)], ratings: ratings)
        XCTAssertEqual(withA.working?.rawID, "v/d")
    }

    func test_defaults_noRatedModels_leavesChoiceToUser() {
        let result = ModelRatings.defaults(from: [descriptor("acme/x")], ratings: ratings)
        XCTAssertNil(result.working)
        XCTAssertNil(result.strong)
    }

    func test_defaults_singleRatedModel_hasNoStrong() {
        let result = ModelRatings.defaults(from: [descriptor("v/a"), descriptor("acme/x")], ratings: ratings)
        XCTAssertEqual(result.working?.rawID, "v/a")
        XCTAssertNil(result.strong)
    }

    // MARK: - Свежесть

    func test_staleness() {
        let measured = Date(timeIntervalSince1970: 1_000_000_000)
        let day: TimeInterval = 86_400
        XCTAssertFalse(ModelRatings.isStale(now: measured.addingTimeInterval(30 * day), measured: measured))
        XCTAssertFalse(ModelRatings.isStale(now: measured.addingTimeInterval(Double(ModelRatings.staleAfterDays) * day), measured: measured))
        XCTAssertTrue(ModelRatings.isStale(now: measured.addingTimeInterval(Double(ModelRatings.staleAfterDays + 1) * day), measured: measured))
        XCTAssertTrue(ModelRatings.isStale(now: measured, measured: nil), "нет даты замера — считаем устаревшим")
    }

    func test_generatedData_isWellFormed() {
        XCTAssertNotNil(ModelRatings.measuredDate, "measuredAt должен быть датой yyyy-MM-dd")
        let keys = ModelRatings.entries.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "ключи уникальны")
        XCTAssertTrue(ModelRatings.entries.allSatisfy { (0...100).contains($0.score) && (0...100).contains($0.qualityScore) })
        for entry in ModelRatings.entries {
            XCTAssertEqual(ModelRatings.key(for: entry.name), entry.key, "ключ записи совпадает с ключом её имени")
        }
        let scores = ModelRatings.entries.map(\.score)
        XCTAssertEqual(scores, scores.sorted(by: >), "данные отсортированы по убыванию")
    }
}
