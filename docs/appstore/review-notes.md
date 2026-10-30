# App Review: заметки для проверяющих и ответы на анкеты

## Notes for the reviewer (вставить в App Review Information → Notes)

BYO Translate is a "bring your own key" translator: it calls an AI provider with the user's own API key. To test it, please use this OpenRouter key (spending limit set by us):

API key: <ВСТАВИТЬ ОТДЕЛЬНЫЙ КЛЮЧ OPENROUTER С ЛИМИТОМ>

1. Open the app → Models → Add connection → OpenRouter → paste the key → Check and continue. Models are pre-filled; tap Done.
2. Selected text: Settings → Apps → Default Apps → Translation → BYO Translate. Select any text in Safari and tap "Translate".
3. Screen translation: in the app's main screen tap "Add the 'Translate Screen' shortcut" and add it in Shortcuts. Run it from the Shortcuts app (or assign it to the Action button) on any screen with text: the translated screenshot appears in Quick Look over the current app.
4. Share sheet: share any image with text from Photos to "BYO Translate".

No account or sign-in is required. The app has no server of its own; requests go directly to the configured provider.

> Ключ для проверки: создать на openrouter.ai отдельный ключ с лимитом (например, 5 $) и рабочей моделью, вписать сюда при отправке и **не коммитить** в репозиторий. После одобрения ключ можно удалить.

## App Privacy (анкета «Конфиденциальность приложения») — рекомендация

- **Data collection:** «Data Not Collected». Обоснование: у разработчика нет сервера, SDK аналитики или рекламы; данные уходят напрямую провайдеру, которого пользователь сам выбрал и с которым у него собственный договор (его ключ). Это толкование «collected» Apple — решение за владельцем аккаунта; при сомнении можно указать «User Content → App Functionality, not linked, no tracking».
- **Tracking:** No.

## Возрастной рейтинг — рекомендация

Нет насилия, азартных игр, рекламы, чатов между пользователями, неограниченного браузера. Приложение переводит то, что пользователь сам выделил или снял. Ожидаемо 4+; если анкета спрашивает про генерацию контента ИИ — ответить, что ИИ используется только для перевода пользовательского текста, без свободного чата.

## Export Compliance

Только системное шифрование (HTTPS, Keychain, CryptoKit) → «None of the algorithms mentioned above» (как в TestFlight).

## Скриншоты (iPhone 6.9"/6.7", 1290×2796 с iPhone 15 Pro Max подходят)

Без личных данных (имён, сумм, номеров счетов). Предлагаемый набор:
1. Экран приложения на иврите + результат «Перевести на месте» поверх него.
2. Шторка перевода выделенного текста в Safari.
3. Режим «Фрагменты» с открытой шторкой перевода фрагмента.
4. Выбор модели с рейтингом.
5. Главная страница настроек («Перевод экрана», модели).
