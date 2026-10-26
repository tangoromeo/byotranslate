import LLMTranslateKit
import ReplayKit
import SwiftUI

/// B8 (экспериментально): «язычок». Один раз запускаем системную трансляцию
/// экрана; дальше окно PiP у края экрана служит кнопкой: «развернуть» — перевод
/// кадра, снятого чуть до нажатия.
struct LiveModeView: View {
    @ObservedObject private var pip = PiPController.shared
    @State private var frameInfo = "—"
    @State private var logText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Text("Экспериментальный режим. Включите трансляцию экрана один раз, затем покажите «язычок»: это окно «картинка в картинке». Уберите его к краю экрана. Нажмите на него и затем на «развернуть» — приложение откроется с переводом того, что было на экране за секунду до нажатия.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("1. Трансляция экрана") {
                HStack {
                    Text("Начать трансляцию")
                    Spacer()
                    BroadcastPickerButton()
                        .frame(width: 44, height: 44)
                }
                LabeledContent("Кадры", value: frameInfo)
            }

            Section("2. Язычок (PiP)") {
                Button("Показать язычок") { pip.start() }
                Button("Убрать язычок") { pip.stop() }
                LabeledContent("Состояние", value: pip.status)
            }

            Section {
                Button("Перевести последний кадр сейчас") { pip.presentLatestFrame() }
            } header: {
                Text("Проверка")
            } footer: {
                Text("Тот же путь, что у «развернуть», но без PiP — чтобы проверить трансляцию отдельно.")
            }

            Section("Журнал событий") {
                Text(logText)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section {
                Text("Кадры экрана хранятся только на устройстве (4 последних) и стираются при остановке трансляции. Они уходят провайдеру модели только когда вы нажимаете «развернуть».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Приватность")
            }
        }
        .navigationTitle("Живой режим")
        .onAppear { pip.prepare(); refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        logText = LiveDebugLog.tail(25)
        guard let directory = pip.framesDirectory else { frameInfo = "нет App Group"; return }
        let frames = FrameRingBuffer(directory: directory).allFrames()
        guard let last = frames.last else { frameInfo = "нет (трансляция не идёт)"; return }
        let age = Date().timeIntervalSince(last.date)
        frameInfo = "\(frames.count) шт., последний \(String(format: "%.1f", age)) с назад"
    }
}

/// Системная кнопка выбора трансляции (`RPSystemBroadcastPickerView`) с нашим расширением.
private struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.tyrex.llmtranslate.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
