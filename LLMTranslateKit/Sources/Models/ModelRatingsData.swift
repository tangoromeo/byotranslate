// СГЕНЕРИРОВАНО: python3 bench/bench.py rank — не править вручную.
// Замер: 2026-10-02, корпус ntrex, seed 1; метод v1.
// Критерий «лучше» = 0.5·качество + 0.3·цена + 0.2·скорость;
// цена 0.03→1 … 3.0→0 $/1000 предл. (лог.), задержка 0.5→1 … 10.0→0 с (лог.),
// качество: 1 если не значимо хуже лидера, иначе 1 − отставание/10 chrF.
// Пересмотр: docs/RATINGS.md.

extension ModelRatings {
    public static let measuredAt = "2026-10-02"
    public static let methodVersion = 1
    public static let entries: [ModelRating] = [
        ModelRating(key: "gemini-2-5-flash-lite", name: "google/gemini-2.5-flash-lite", score: 99, sentences: 100),
        ModelRating(key: "deepseek-v3-2", name: "deepseek/deepseek-v3.2", score: 84, sentences: 100),
        ModelRating(key: "qwen3-5-plus", name: "qwen/qwen3.5-plus-20260420", score: 83, sentences: 100, disableReasoningRecommended: true),
        ModelRating(key: "gpt-4-1-mini", name: "openai/gpt-4.1-mini", score: 79, sentences: 100),
        ModelRating(key: "mistral-large-2512", name: "mistralai/mistral-large-2512", score: 75, sentences: 91),
        ModelRating(key: "gpt-5-4", name: "openai/gpt-5.4", score: 70, sentences: 20),
        ModelRating(key: "gpt-5-4-mini", name: "openai/gpt-5.4-mini", score: 68, sentences: 100),
        ModelRating(key: "claude-sonnet-5-5", name: "anthropic/claude-sonnet-5.5", score: 63, sentences: 100),
        ModelRating(key: "claude-haiku-4-5", name: "anthropic/claude-haiku-4.5", score: 59, sentences: 100),
        ModelRating(key: "gemini-3-8-flash", name: "google/gemini-3.8-flash", score: 52, sentences: 20),
        ModelRating(key: "gemini-3-1-pro-preview", name: "google/gemini-3.1-pro-preview", score: 50, sentences: 20),
    ]
}
