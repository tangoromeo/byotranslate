import SwiftUI
import TranslationUIProvider

@main
final class TranslateExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslateSheetView(context: context)
        }
    }
}

// Этап 0, разбор Swift 6 strict concurrency вокруг TranslationUIProvider:
// `TranslationUIProviderContext` — protocol (не class), не Sendable, и SDK
// нигде не гарантирует, из какого actor-контекста framework вызывает
// content-замыкание `TranslationUIProviderSelectedTextScene.init(content:)`
// (сам init помечен `@MainActor`, а тип параметра-замыкания — нет).
// Из-за этого простой `let context: any TranslationUIProviderContext` в
// `View` (implicitly MainActor через SwiftUI) даёт то ошибку "sending
// risks causing data races" на вызове инициализатора, то (при
// `nonisolated init`) ошибку "main actor-isolated property can not be
// mutated from a nonisolated context" — сама MainActor-изоляция
// stored property выводится из конформанса View, а не из init.
// `nonisolated(unsafe)` — осознанный эскейп-хэтч: framework гарантирует
// однопоточное использование context в рамках одной шторки перевода,
// формальной Sendable-аннотации в SDK для этого протокола просто нет.
struct TranslateSheetView: View {
    nonisolated(unsafe) let context: any TranslationUIProviderContext

    private var reversed: String {
        guard let text = context.inputText, !text.characters.isEmpty else { return "" }
        return String(text.characters.reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.inputText ?? "")
                .foregroundStyle(.secondary)

            Text(reversed)
                .font(.headline)

            Button {
                // Расхождение п. 4.5 ТЗ разрешено: SDK-интерфейс
                // (arm64e-apple-ios.swiftinterface), справочник фреймворка
                // TranslationUIProviderContext и штатный Xcode-темплейт
                // "Translation Provider Extension" сходятся на
                // `finish(translation:)`. Статья Apple "Preparing your app
                // to be the default translation app" называет
                // `finish(replacingWithTranslation:)` — это устаревшая
                // сигнатура, компилятором не подтверждается.
                context.finish(translation: AttributedString(reversed))
            } label: {
                Text("Заменить")
            }
            .disabled(!context.allowsReplacement)
        }
        .padding(8)
    }
}
