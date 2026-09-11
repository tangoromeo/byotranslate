import SwiftUI
import WidgetKit

/// Раздел 10.5 ТЗ (E3): кнопка Пункта управления, запускающая
/// `TranslateLatestScreenshotIntent`. Сам виджет не трогает ни настройки, ни
/// Keychain — вся работа (фото, сеть, перевод) идёт внутри интента, который
/// выполняется в процессе основного приложения (`openAppWhenRun = true`),
/// не здесь.
@main
struct LLMTranslateControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tyrex.llmtranslate.control.translatescreenshot") {
            ControlWidgetButton(action: TranslateLatestScreenshotIntent()) {
                Label("Перевести скриншот", systemImage: "text.viewfinder")
            }
        }
        .displayName("Перевести скриншот")
        .description("Переводит последний снимок экрана.")
    }
}
