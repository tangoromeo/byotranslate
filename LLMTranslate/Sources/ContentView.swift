import SwiftUI
import UIKit
import LLMTranslateKit

/// Раздел 10.4 ТЗ: экран, на который приходят E2/E3 — `PendingImageTranslation`
/// заполняется App Intent'ом, приложение выходит на передний план
/// (`openAppWhenRun = true`) и показывает результат здесь.
struct ContentView: View {
    @ObservedObject private var pending = PendingImageTranslation.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsView()
            .fullScreenCover(isPresented: isPresentingPendingTranslation) {
                pendingTranslationSheet
            }
            // Раздел 10.4 ТЗ: intent мог выполниться в отдельном процессе
            // (см. PendingImageTranslation) — на каждый выход на передний
            // план проверяем App Group на оставленный хендофф, не только
            // при первом появлении вью.
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    pending.consumeHandoff(appGroupSuiteName: SharedIdentifiers.appGroup)
                case .background:
                    // Результат показывается один раз: если приложение
                    // свернули (в том числе свайпом, без «Готово»), при
                    // следующем запуске с иконки должен открыться экран
                    // настроек, а не последний переведённый скриншот.
                    pending.discardOnBackground(appGroupSuiteName: SharedIdentifiers.appGroup)
                default:
                    break
                }
            }
            .task {
                pending.consumeHandoff(appGroupSuiteName: SharedIdentifiers.appGroup)
            }
    }

    private var isPresentingPendingTranslation: Binding<Bool> {
        Binding(
            get: { pending.imageData != nil || pending.error != nil },
            set: { isPresented in if !isPresented { pending.clear() } }
        )
    }

    @ViewBuilder
    private var pendingTranslationSheet: some View {
        NavigationStack {
            Group {
                if let imageData = pending.imageData {
                    ImageTranslationView(originalImageData: imageData, appGroupSuiteName: SharedIdentifiers.appGroup)
                } else if let error = pending.error {
                    ContentUnavailableView(error.localizedUserMessage, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Перевод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        pending.clear()
                        returnToPreviousApp()
                    }
                }
            }
        }
    }

    /// E2/E3 приводят приложение на передний план поверх того, что было
    /// открыто до этого (раздел 10.4 ТЗ) — официального API «вернуться
    /// туда, откуда пришёл» у обычного приложения нет (в отличие от Share
    /// Extension, где `completeRequest()` делает это сам). Это
    /// неофициальный, но широко используемый приём: `UIApplication`
    /// отвечает на тот же по имени селектор, что и `URLSessionTask.suspend`
    /// — вызов через `performSelector` сворачивает приложение так же, как
    /// нажатие Home, открывая то, что было активно до нас.
    private func returnToPreviousApp() {
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }
}

#Preview {
    ContentView()
}
