# BYO Translate

**English** · [Русский](#byo-translate-по-русски)

Translate text and screenshots on iOS with the LLM **you** choose — and with your own API key. No accounts, no ads, no analytics, no middleman server.

> iOS 18.4+ · Swift 6 · SwiftUI · zero third-party dependencies

## Why

- Machine translation from the big free services is often stiff or plain wrong, especially for idioms, UI strings and right-to-left languages. A good LLM does much better.
- Translating a screen on iOS is clumsy: take a screenshot, open an app, copy text, paste, wait. Here it is one tap on the Action Button.
- You decide who sees your text. It goes straight from your phone to the provider you configured, and nowhere else.

## Features

**Several ways in**

- **Select text anywhere → Translate.** Works as the system translation app (*Settings → Apps → Default Apps → Translation*), so the standard sheet appears in Safari, Mail, Messages and everywhere else.
- **Screenshot translation on the Action Button.** An App Intent ("Translate Latest Screenshot") plus a Control Center control. Bind it once, then a single press translates what is on screen.
- **Share sheet.** Send any image to *BYO Translate* from Photos or any other app.

**Screenshot translation, three views**

| View | What you get |
| --- | --- |
| **Whole screen** (default) | The translation drawn on top of the original as semi-transparent labels, colored to match the background. Find the right menu item at a glance — handy for foreign banking apps. Pinch to zoom, tap a label for details. |
| **Fragments** | Detected text blocks are outlined; tap one to translate only that block in a bottom sheet. |
| **Text** | A plain, continuous translation of the whole screenshot. |

Text regions are found on-device (Apple Vision, language-independent, so Hebrew and Arabic work). In *Whole screen* and *Fragments* only small crops of the screenshot are sent to the model; *Text* sends the whole image. Nothing is written to disk.

**Translation quality tools**

- Two model slots: a fast **working** model and a stronger one behind the **More precise** button.
- **Explain** — notes on idioms, ambiguity and tone after the translation.
- **Dictionary mode** for a single selected word: top translation, alternatives, part of speech, transliteration.
- **Glossary** — terms that must always be translated the same way.
- Editable system prompts; the target language is a primary/secondary pair, picked automatically from the detected source language.
- Right-to-left results are aligned correctly.

**Practicalities**

- Providers: any **OpenAI-compatible** endpoint, **Anthropic**, **Google Gemini**. Model picker with a list fetched from the provider.
- Local cache for text translations, monthly usage counter, and a log of the last 20 requests (metadata only — never text, images or keys).
- UI in English and Russian.

## Privacy

- API keys live in the iOS Keychain.
- Selected text and images are sent only to the endpoint you configured. There is no telemetry and no server of ours.
- Screenshots and crops are processed in memory and are not written to disk.
- Cached text translations stay on the device and can be cleared in the app.

## Getting started

1. Get an API key from a provider (OpenAI-compatible, Anthropic or Gemini).
2. Open the app, add the key and pick a model for the *working* slot. For screenshots the model must understand images.
3. Set BYO Translate as the default translation app and, optionally, bind the screenshot shortcut to the Action Button. The in-app **Get started** screen walks through both.

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open LLMTranslate.xcodeproj
```

Set your own `DEVELOPMENT_TEAM` in `project.yml`. Acting as the system translation app requires a paid Apple Developer Program team (the capability is not available to personal teams).

Unit tests for `LLMTranslateKit` live in `LLMTranslateKitTests`. See `NOTES.md` for known build-environment quirks, `docs/TZ.md` for the specification and `docs/BACKLOG.md` for what is planned.

## Project layout

| Path | Purpose |
| --- | --- |
| `LLMTranslate/` | The host app: settings, onboarding, App Intents |
| `LLMTranslateKit/` | Shared framework: providers, prompts, orchestration, cache, screenshot pipeline, shared UI |
| `LLMTranslateTextExt/` | System translation extension (select text → Translate) |
| `LLMTranslateShareExt/` | Share extension for images |
| `LLMTranslateControl/` | Control Center control |

---

# BYO Translate по-русски

[English](#byo-translate) · **Русский**

Перевод текста и скриншотов на iOS той LLM, которую выбираете **вы**, и по вашему собственному API-ключу. Без аккаунтов, рекламы, аналитики и промежуточного сервера.

> iOS 18.4+ · Swift 6 · SwiftUI · без сторонних зависимостей

## Зачем

- Машинный перевод больших бесплатных сервисов часто деревянный или просто неверный, особенно на идиомах, интерфейсных строках и языках с письмом справа налево. Хорошая LLM справляется заметно лучше.
- Перевод экрана в iOS неудобен: снимок, открыть приложение, скопировать текст, вставить, подождать. Здесь это одно нажатие на Action Button.
- Вы сами решаете, кто видит ваш текст. Он уходит прямо с телефона к настроенному вами провайдеру и больше никуда.

## Возможности

**Несколько способов запуска**

- **Выделить текст где угодно → «Перевести».** Приложение работает как системный переводчик (*Настройки → Приложения → Приложения по умолчанию → Перевод*), поэтому стандартная шторка появляется в Safari, «Почте», «Сообщениях» и везде остальном.
- **Перевод скриншота на Action Button.** App Intent («Перевести последний скриншот») и кнопка в Пункте управления. Один раз привязали, дальше одно нажатие переводит то, что на экране.
- **Меню «Поделиться».** Отправьте любое изображение в *BYO Translate* из «Фото» или другого приложения.

**Перевод скриншота: три вида**

| Вид | Что получаете |
| --- | --- |
| **Весь экран** (по умолчанию) | Перевод полупрозрачными плашками поверх оригинала, цвет плашки подбирается под фон. Нужный пункт меню находится с одного взгляда — удобно для иностранных банковских приложений. Щипок для увеличения, тап по плашке открывает подробности. |
| **Фрагменты** | Найденные блоки текста обведены; тап по блоку переводит только его и показывает результат в шторке. |
| **Текст** | Обычный связный перевод всего скриншота. |

Области с текстом находятся на устройстве (Apple Vision, не зависит от языка, поэтому иврит и арабский работают). В режимах «Весь экран» и «Фрагменты» модели уходят только небольшие фрагменты скриншота; режим «Текст» отправляет снимок целиком. На диск ничего не записывается.

**Инструменты качества перевода**

- Два слота моделей: быстрая **рабочая** и более сильная за кнопкой **«Точнее»**.
- **«Пояснить»** — комментарии к идиомам, неоднозначностям и тону после перевода.
- **Словарный режим** для одного выделенного слова: основной перевод, альтернативы, часть речи, транслитерация.
- **Глоссарий** — термины, которые всегда переводятся одинаково.
- Редактируемые системные промпты; целевой язык задаётся парой основной/запасной и выбирается автоматически по определённому языку оригинала.
- Результат на языках с письмом справа налево выровнен правильно.

**Практические мелочи**

- Провайдеры: любой **OpenAI-совместимый** endpoint, **Anthropic**, **Google Gemini**. Выбор модели из списка, который запрашивается у провайдера.
- Локальный кэш переводов текста, месячный счётчик расхода и журнал последних 20 запросов (только метаданные — никогда не текст, изображения или ключи).
- Интерфейс на английском и русском.

## Приватность

- API-ключи хранятся в Keychain iOS.
- Выделенный текст и изображения отправляются только на настроенный вами endpoint. Телеметрии и нашего сервера нет.
- Скриншоты и фрагменты обрабатываются в памяти и на диск не записываются.
- Кэш переводов текста остаётся на устройстве и очищается в приложении.

## Быстрый старт

1. Получите API-ключ у провайдера (OpenAI-совместимого, Anthropic или Gemini).
2. Откройте приложение, добавьте ключ и выберите модель для *рабочего* слота. Для скриншотов модель должна понимать изображения.
3. Назначьте BYO Translate переводчиком по умолчанию и, при желании, привяжите команду для скриншота к Action Button. Оба шага разобраны на экране **«Как начать»** в приложении.

## Сборка

Проект Xcode генерируется из `project.yml` через [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open LLMTranslate.xcodeproj
```

Укажите свой `DEVELOPMENT_TEAM` в `project.yml`. Работа в роли системного переводчика требует платной команды Apple Developer Program (для личных команд эта возможность недоступна).

Юнит-тесты `LLMTranslateKit` лежат в `LLMTranslateKitTests`. Особенности окружения сборки описаны в `NOTES.md`, спецификация — в `docs/TZ.md`, планы — в `docs/BACKLOG.md`.

## Структура проекта

| Путь | Назначение |
| --- | --- |
| `LLMTranslate/` | Приложение-хост: настройки, онбординг, App Intents |
| `LLMTranslateKit/` | Общий фреймворк: провайдеры, промпты, оркестрация, кэш, обработка скриншотов, общий UI |
| `LLMTranslateTextExt/` | Системное расширение перевода (выделить текст → «Перевести») |
| `LLMTranslateShareExt/` | Расширение «Поделиться» для изображений |
| `LLMTranslateControl/` | Кнопка в Пункте управления |
