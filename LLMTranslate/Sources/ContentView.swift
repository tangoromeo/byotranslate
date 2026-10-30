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
                    ScreenshotRegionsView(originalImageData: imageData, appGroupSuiteName: SharedIdentifiers.appGroup)
                } else if let error = pending.error {
                    ContentUnavailableView(error.localizedUserMessage, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Перевод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Вернуться в прежнее приложение у обычного приложения нет
                    // публичного API; неофициальный приём с `suspend` убран перед
                    // App Store (риск отказа по 2.5.1, к тому же не срабатывал).
                    // Без ухода из приложения работает «Перевести на месте».
                    Button("Готово") {
                        pending.clear()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
