# NOTES.md — этап 0 (разведка)

Среда проверки: macOS 26.6.2, Xcode 26.6 (build 17F113), iOS SDK 26.5,
симулятор iPhone 16 Pro / iOS 18.6 (com.apple.CoreSimulator.SimRuntime.iOS-18-6).
Физического устройства с iOS 18.4+ в этой среде нет — там, где факт
принципиально требует реального железа, это указано явно, значение не
подставлено «правдоподобно».

---

## 1. Фактическая сигнатура метода завершения (п. 4.5 ТЗ)

**`func finish(translation: AttributedString?)`**

Расхождение разрешено тремя независимыми источниками, все указывают на
один и тот же вариант — не тот, что в статье-туториале:

1. **SDK swiftinterface** (источник истины, проверяется компилятором):
   `/Applications/Xcode.app/.../iPhoneOS.sdk/System/Library/Frameworks/TranslationUIProvider.framework/Modules/TranslationUIProvider.swiftmodule/arm64e-apple-ios.swiftinterface`
   ```swift
   public protocol TranslationUIProviderContext : Observation.Observable {
     var inputText: Foundation.AttributedString? { get }
     var allowsReplacement: Swift.Bool { get }
     func finish(translation: Foundation.AttributedString?)
     func expandSheet()
   }
   ```
2. **Справочник фреймворка** (developer.apple.com/documentation/translationuiprovider/translationuiprovidercontext):
   явно называет `finish(translation:)` и подробно перечисляет тот же контракт.
3. **Официальный Xcode-темплейт** «Translation Provider Extension»
   (`.../iPhoneOS.platform/.../Templates/.../Translation Provider Extension.xctemplate/TranslationProvider.swift`),
   тот же файл, что ставится через Xcode → New Target → Translation:
   вызывает `context.finish(translation: AttributedString(translated))`.

Статья-тьюториал «Preparing your app to be the default translation app»
(тот же сайт, другая страница) использует устаревшее
`context.finish(replacingWithTranslation: AttributedString(translated))` —
это не компилируется против текущего SDK. Доверять статье в этой части
нельзя, руководствоваться нужно `TranslationUIProviderContext` из
справочника/SDK.

Любопытная деталь: сэмпл в этой же статье в реализации `translate()`
реверсит текст (`String(toTranslate.characters.reversed())`) — то есть
пункт ТЗ «вывести текст задом наперёд, как в сэмпле Apple» отсылает
именно к этому официальному примеру, и реализация в этапе 0
(`LLMTranslateTextExt/Sources/TranslateExtension.swift`) сделана так же.

### Побочная находка: Swift 6 strict concurrency vs SDK

`TranslationUIProviderSelectedTextScene.init(content:)` помечен
`@MainActor`, но тип параметра-замыкания
(`(any TranslationUIProviderContext) -> Content`) — нет, а сам
`TranslationUIProviderContext` не `Sendable`. Под Swift 6 strict
concurrency это даёт ошибку компиляции на прямой реализации из сэмпла
Apple («sending 'context' risks causing data races»). Явная пометка
параметра замыкания `@MainActor` не подходит — ломает соответствие типов
с сигнатурой SDK. Рабочее решение, использованное в
`TranslateSheetView`: `nonisolated(unsafe) let context: any
TranslationUIProviderContext` — осознанный эскейп-хэтч, framework не даёт
формальной Sendable-аннотации для этого протокола, но гарантирует
однопоточное использование в рамках одной шторки перевода. Если Apple
свежее SDK когда-нибудь дополнит протокол `@preconcurrency`/`Sendable` —
эту аннотацию можно будет снять.

---

## 2. Фактические лимиты памяти обоих расширений

**Не определено — нужен реальный iOS-девайс, в этой среде его нет.**

iOS Simulator процессы расширений выполняются как обычные macOS-процессы
под виртуальной памятью хоста — на них не действует механизм jetsam
реального iOS, поэтому «наращивать аллокацию до jetsam-килла» в
симуляторе даёт число, не имеющее отношения к реальному лимиту на
устройстве. Подставлять здесь правдоподобную цифру («обычно говорят про
~30 МБ для сегодняшних share extensions» и т.п.) — то самое действие,
от которого явно предостерегает ТЗ.

**Как измерить на этапе 3** (когда встанет вопрос обработки изображений):
на реальном устройстве через Xcode → Debug → Simulate Memory Warning /
Memory Graph при живой отладке `LLMTranslateTextExt` и будущего
`LLMTranslateShareExt`, либо через Instruments (Allocations) с
постепенным ростом тестового буфера до `EXC_RESOURCE
RESOURCE_TYPE_MEMORY` (jetsam-килл) в консоли устройства. Практический
вывод риска раздела 17 ТЗ остаётся в силе независимо от точной цифры:
даунскейл изображения нужно делать **до** кодирования в base64, не
держать одновременно оригинал/уменьшенную копию/base64-строку.

---

## 3. Фактический список `supportedRecognitionLanguages()` и ответ про иврит (п. 10.6)

Измерено на **симуляторе** iPhone 16 Pro, iOS 18.6, через
`Vision.RecognizeTextRequest().supportedRecognitionLanguages`
(revision по умолчанию — `.revision3`, `recognitionLevel` по умолчанию —
`.accurate`). 18 языков:

```
ar-Arab-SA, ars-Arab-SA, de-Latn-DE, en-Latn-US, es-Latn-ES, fr-Latn-FR,
it-Latn-IT, ja-Jpan-JP, ko-Kore-KR, pt-Latn-BR, ru-Cyrl-RU, th-Thai-TH,
uk-Cyrl-UA, vi-Latn-VT, yue-Hans-CN, yue-Hant-HK, zh-Hans-CN, zh-Hant-TW
```

**Иврит (`he`) — НЕ поддерживается.** Подтверждает риск из раздела 17
ТЗ («Vision OCR не поддерживает иврит»): локальный OCR как опциональный
быстрый путь (п. 10.6) для пары иврит→русский не сработает при любом
раскладе, придётся полагаться на основной путь — прямую отправку
изображения в мультимодальную модель.

Оговорка: список получен в **симуляторе**, не на устройстве. Apple не
документирует гарантию идентичности набора языков Vision между
симулятором и устройством; конкретно для иврита это ничего не меняет
(он использует другую систему письма, которой в списке просто нет —
маловероятно, что на устройстве появится по расхождению
симулятор/девайс), но список остальных 18 языков стоит перепроверить на
реальном железе на этапе 3, если появится время.

---

## 4. Фактический лимит числа App Shortcuts (п. 10.9)

**10.** Дословно из Apple Human Interface Guidelines → App Shortcuts
(developer.apple.com/design/human-interface-guidelines/app-shortcuts):
«Each app can include up to 10 App Shortcuts.» Справочник API
(`AppShortcutsBuilder`, `AppShortcutsProvider`) эту цифру не публикует —
она только в HIG, не в API-референсе, поэтому релевантен именно
дизайн-документ, а не страница протокола. Наши два шортката из раздела
10.9 ТЗ (`TranslateLatestScreenshotIntent`, `TranslateImageIntent`) —
далеко от лимита.

---

## 5. Существование рабочего deep link в раздел стандартных программ (раздел 12, п.1)

**Есть, но ведёт на уровень выше, чем просили в ТЗ.**

Публичный, документированный (не приватный `App-Prefs:`) API:
`UIApplication.openDefaultApplicationsSettingsURLString` (iOS 18.3+,
значение строки — `app-settings:default-applications`, вычислено из
`strings` по `UIKitCore` симулятора и подтверждено официальной
документацией developer.apple.com/documentation/uikit/uiapplication/opendefaultapplicationssettingsurlstring).

Проверено вживую на симуляторе: вызов
`await UIApplication.shared.open(URL(string:
UIApplication.openDefaultApplicationsSettingsURLString)!)` из
`LLMTranslate` вернул `true` и реально открыл Настройки — но
**на экран «Настройки → Приложения»** (верхний список, где первым
пунктом идёт «Приложения по умолчанию»), а не сразу на сам раздел
«Приложения по умолчанию» и тем более не на конкретную строку
«Перевод» внутри него. Скриншот подтверждён дважды подряд (устойчивое
конечное состояние, не промежуточный кадр анимации).

Итог для онбординга (раздел 12, п.1 ТЗ): использовать этот deep link
стоит — он безопаснее и на один тап ближе, чем открытие Настроек с нуля
через `UIApplication.openSettingsURLString` — но текст онбординга должен
явно попросить пользователя самостоятельно нажать «Приложения по
умолчанию» → «Перевод», а не обещать, что это произойдёт автоматически.
Точной, программной ссылки на саму строку «Перевод» внутри «Приложения
по умолчанию» не существует.

---

## 6. Расхождение с таблицей ТЗ 6.2: Gemini `streamGenerateContent` требует `?alt=sse`

Обнаружено при реализации `GeminiProvider` (этап 2/3 ТЗ v1.2, слоты +
Anthropic/Gemini адаптеры). Таблица раздела 6.2 ТЗ описывает эндпоинт как
`{baseURL}/models/{model}:streamGenerateContent` без оговорок про параметры
запроса. По актуальной документации Google AI (проверено веб-поиском на
момент реализации): без query-параметра `alt=sse` этот эндпоинт отдаёт один
большой JSON-массив целиком, а не построчный SSE — то есть построчный
парсинг (`data: {...}\n\n`), который держит вся остальная стриминговая
инфраструктура проекта (`SSELineAssembler` и т. д.), для Gemini без этого
параметра не сработает вовсе.

Исправлено в `GeminiProvider.buildRequest`: URL собирается с
`?alt=sse` явно. Также у Gemini, в отличие от OpenAI (`[DONE]`) и Anthropic
(`message_stop`), нет строкового/событийного терминатора конца потока —
конец стрима определяется закрытием соединения после HTTP 200
(`SSEStreamCompletionPolicy.closeIsSuccess`).

---

## 7. Ещё один баг этой сборки Xcode 26.6: `actool`/`CompileAssetCatalog` не запускается штатно

Тот же класс проблем, что с `-destination` (этап 0) и с резолвом дестинации
`bundle.unit-test`-таргета (этап 1) — обходные пути `xcodebuild -target ...`
(без `-scheme`) в этой сборке пропускают этап компиляции asset catalog:
`Assets.car` не создаётся, `CFBundleIconName`/`CFBundleIcons` не попадают в
Info.plist, иконка приложения никогда не встраивается в бандл — при этом
`BUILD SUCCEEDED`, без единой ошибки в логе.

Попытка собрать через `-scheme LLMTranslate -destination ...` (в обход
таргет-инвокации) наткнулась на тот же баг резолва симулятора, что и раньше:
схема видит только физические устройства-плейсхолдеры
(`iOS 26.5 is not installed`), ни одного симулятора среди destinations нет,
несмотря на то что у самого таргета `GENERATE_INFOPLIST_FILE: true`
(в отличие от исходного случая с расширениями).

Дополнительно у `actool` при ручном вызове обнаружился третий, отдельный
баг toolchain'а: с флагом `--minimum-deployment-target` он падает с
`exit 1` на проверке `No simulator runtime version from [...] available to
use with iphonesimulator SDK version ...` — проверка не имеет отношения к
самой компиляции иконки и просто блокирует весь вызов. Без этого флага
actool лишь предупреждает о его отсутствии, но иконки собирает корректно
(и по-прежнему возвращает `exit 1` из-за той же проверки рантайма — поэтому
факт успеха проверяется по появлению `partial.plist`, не по exit code).

**Обходной путь** (`project.yml`, `postbuildScripts` таргета `LLMTranslate`):
ручной вызов `actool --platform "$PLATFORM_NAME" --app-icon AppIcon
--output-partial-info-plist ... --compile ...` по `Assets.xcassets`, копирование
получившихся `AppIcon*.png` в `$UNLOCALIZED_RESOURCES_FOLDER_PATH` и
`PlistBuddy -c "Merge ... partial.plist"` в уже сгенерированный Info.plist.
Работает только для симулятора (`$PLATFORM_NAME` = `iphonesimulator`); для
реальной archive-сборки под устройство/App Store этот скрипт не проверялся
и, скорее всего, потребует отдельного разбора — на реальном Xcode GUI
(если этот баг toolchain'а к тому моменту не будет исправлен Apple) этот
постбилд-скрипт можно будет просто убрать.

---

## Статус блокирующего критерия этапа 0

Собрано и проверено:

- Xcode-проект (`LLMTranslate.xcodeproj`, сгенерирован через `xcodegen`
  из `project.yml`) с таргетами `LLMTranslate` (app) и
  `LLMTranslateTextExt` (`extensionkit-extension`).
- Entitlement `com.apple.developer.translation-app` — в
  `LLMTranslate/Resources/LLMTranslate.entitlements`.
- Info.plist-ключ `com.apple.developer.translation-ui-provider.network-access`
  (Boolean, true) — в `LLMTranslate/Resources/Info.plist`.
- `LLMTranslateTextExt` собирается, ставится в симулятор и **виден
  системе**: `pluginkit -m -v -i com.tyrex.llmtranslate.textext`
  внутри симулятора подтверждает регистрацию расширения по
  extension point `com.apple.public.translation-ui-provider`.
- Оба таргета компилируются под Swift 6 language mode / strict
  concurrency без ошибок (см. находку про `nonisolated(unsafe)` выше).
- **Подтверждено вживую, интерактивно, на симуляторе (iPhone 16 Pro,
  iOS 18.6):** Safari → en.wikipedia.org/wiki/Moth → выделение слова
  «Moths» → «Перевести» в системном меню → системная шторка «Translate»
  явно указывает получателя: «Выбранный контент будет отправлен в
  LLMTranslate для обработки перевода» → после «Продолжить» открывается
  **наша** шторка: исходный текст «Moths», под ним «shtoM» (реверс — как
  в сэмпле Apple из п. 4.3 ТЗ), кнопка «Заменить» корректно задизейблена
  (Safari — нередактируемое поле, `allowsReplacement == false`).
  Блокирующий критерий этапа 0 выполнен полностью.

(Изначально интерактивный тач-ввод в симулятор был недоступен, так как
`xcode-select` указывал на Command Line Tools, а не на `Xcode.app` —
это исправлено самим пользователем командой `sudo xcode-select -s
/Applications/Xcode.app/Contents/Developer` по ходу сессии.)

## Известные особенности окружения (не факты ТЗ, но важно для этапа 1+)

- **`xcodebuild -scheme ... -destination ...` не находит ни одного
  симулятора** (ни `-showdestinations`, ни `build`) для любого таргета
  с `GENERATE_INFOPLIST_FILE: false` + статический `Info.plist` — в
  этой конкретной сборке Xcode 26.6 показывает только физические
  устройства, «Supported platforms for the buildables in the current
  scheme is empty». Обходной путь, использованный на этапе 0:
  `xcodebuild -target <T> -sdk iphonesimulator -arch arm64 build` (без
  `-scheme`/`-destination`) — собирает нормально, `-showBuildSettings`
  подтверждает `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`. Похоже
  на баг конкретно этой сборки Xcode, а не на ошибку конфигурации
  проекта — воспроизведён на минимальном одно-таргетном проекте.
- **`EXAppExtensionAttributes` для `extensionkit-extension`-таргета
  должен быть на верхнем уровне Info.plist**, не вложен в `NSExtension`.
  Официальный темплейт «Translation Provider Extension» вкладывает его
  под `NSExtension` — но это описание слота подстановки шаблона, а не
  реальной итоговой структуры; факт подтверждён по темплейту «App
  Intents Extension» (`Info.plist:EXAppExtensionAttributes` как
  отдельный узел верхнего уровня) и напрямую по логам CoreSimulator
  (`installcoordinationd`): `exAppExtensionAttributes must be set in
  placeholder attributes for an ExtensionKit app extension placeholder`
  при вложенном варианте, установка проходит только с ключом на верхнем
  уровне.
- Симулятор с ad-hoc-подписью («Sign to Run Locally») не embed-ит
  entitlements через классическую code-signature (`codesign -d
  --entitlements` показывает пустой словарь) — актуальная схема
  встраивает entitlements линковщиком в секцию `__TEXT,__entitlements`
  бинарника напрямую (проверено `segedit -extract __TEXT
  __entitlements`). Это нормально для локальной разработки без
  Team ID; на реальном устройстве потребуется полноценный provisioning
  profile с включённой capability Translation для App ID — это
  требует входа в Apple Developer аккаунт, отдельный шаг за пределами
  этапа 0.
- **Схема `bundle.unit-test`-таргета в этой сборке Xcode 26.6 не
  резолвит ни одной destination для iOS Simulator** ни через
  `-showdestinations`, ни через `test`/`build-for-testing` — независимо
  от `GENERATE_INFOPLIST_FILE`, `SUPPORTS_MACCATALYST` и наличия
  test-host приложения. Воспроизведено на полностью минимальном проекте
  (app + один unit-test таргет, ничего специфичного для LLMTranslate).
  Похоже на отдельный баг конкретно этой Xcode-сборки для типа таргета
  `com.apple.product-type.bundle.unit-test` — того же рода, что и баг с
  `-destination` из этапа 0, но с другим триггером (там чинилось через
  `-target`/`-sdk`, здесь `xcodebuild test` в принципе не работает без
  `-scheme`). Реальный `.xctest`-бандл при этом собирается без ошибок:
  `xcodebuild -target LLMTranslateKitTests -sdk iphonesimulator build`
  проходит чисто, значит дело именно в резолве дестинации, не в
  конфигурации таргета.

  Обходной путь для этапа 1: временный SPM-пакет в scratchpad
  (`Package.swift` с `.target`/`.testTarget`, пути — симлинки на
  реальные `LLMTranslateKit/Sources` и `LLMTranslateKitTests`, не
  коммитится в репозиторий), тесты гоняются через `swift test` на
  macOS. Логика вся платформонезависимая (`Foundation`, `Security`,
  `NaturalLanguage` — все три доступны и на macOS), поэтому это честная
  проверка тех же исходников, просто не через iOS-симулятор. На реальном
  устройстве/при наличии рабочего Xcode это же самое стоит перепроверить
  через штатный `⌘U` — там эта проблема резолва дестинации не должна
  воспроизводиться (она специфична для этой конкретной сборки Xcode).
