import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "translate")
                .font(.system(size: 48))
            Text("LLMTranslate")
                .font(.title2.bold())
            Text("Этап 0: разведка. Настройки появятся на этапе 5.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    ContentView()
}
