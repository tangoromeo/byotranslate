import Foundation

/// Раздел 8 ТЗ — системные промпты по умолчанию и подстановка глоссария.
public enum PromptBuilder {
    /// Раздел 8.1 ТЗ.
    public static let defaultTextSystemPrompt = """
    Ты — переводчик. Переведи текст пользователя на {targetLanguage}.

    Правила:
    - Выводи ТОЛЬКО перевод. Никаких пояснений, преамбул, извинений, кавычек вокруг результата.
    - Сохраняй регистр, пунктуацию, переносы строк и разметку исходника.
    - Сохраняй без перевода: имена собственные, названия компаний и продуктов,
      идентификаторы, код, URL, email, числа, единицы измерения.
    - Если текст — фрагмент без контекста, переводи его как фрагмент,
      не достраивай предложение.
    {glossarySection}
    """

    /// Раздел 8.2 ТЗ.
    public static let defaultImageSystemPrompt = """
    На изображении — снимок экрана или фотография текста.
    Извлеки весь текст и переведи его на {targetLanguage}.

    Правила:
    - Выводи ТОЛЬКО перевод, без описания изображения и без комментариев.
    - Сохраняй структуру: абзацы, списки, таблицы, порядок блоков сверху вниз.
    - Интерфейсные элементы (кнопки, пункты меню, поля) выводи отдельными строками
      в том порядке, в котором они расположены.
    - Не переводи: имена собственные, названия компаний и продуктов, URL, email,
      номера счетов, идентификаторы, числа.
    - Нечитаемый фрагмент помечай как [неразборчиво], не додумывай.
    {glossarySection}
    """

    /// Раздел B6, этап 3: лист фрагментов скриншота (кропы друг под другом,
    /// номер слева) → JSON. Не редактируется пользователем: формат ответа
    /// жёстко привязан к `RegionTranslationParser`.
    public static let defaultRegionsSystemPrompt = """
    На изображении — фрагменты экрана приложения, расположенные друг под другом.
    Слева от каждого фрагмента крупный номер. Переведи текст каждого фрагмента на {targetLanguage}.

    Правила:
    - Ответ — ТОЛЬКО JSON-массив без пояснений и без обрамления: [{"n":1,"t":"перевод"},{"n":2,"t":"перевод"}].
    - "n" — номер фрагмента, "t" — его перевод. Номер на картинке — не часть текста, не переводи его.
    - Переводи каждый фрагмент независимо, сохраняя переносы строк внутри фрагмента как \\n.
    - Фрагмент — это пункт интерфейса (меню, кнопка, подпись): переводи коротко, как принято в интерфейсах.
    - Не переводи: имена собственные, названия компаний и продуктов, URL, email,
      номера счетов, идентификаторы, числа, суммы и валюты.
    - Если фрагмент нечитаем, верни для него "t": "".
    - Фрагмент, который уже на {targetLanguage}, верни без изменений.
    {glossarySection}
    """

    /// Раздел 8.3 ТЗ v1.2: надстройка для режима `.withNotes` — добавляется
    /// к промпту `.plain`, не заменяет его. Редактируема пользователем
    /// (третий редактор промптов, раздел 13.3 ТЗ).
    public static let defaultNotesAddendum = """
    После перевода выведи отдельной строкой маркер ⟦NOTES⟧, а под ним — краткие пояснения.

    В пояснениях допустимо ТОЛЬКО следующее:
    - альтернативные варианты перевода неоднозначных мест, не более трёх;
    - расшифровка идиом, реалий, игры слов;
    - пометка, если тон или регистр исходника передать не удалось;
    - транслитерация имён собственных.

    Запрещено: пересказывать текст, оценивать его, рассуждать о языке вообще,
    объяснять очевидное, извиняться.

    Каждое пояснение — одна строка, начинается с «— ».
    Если пояснять нечего, не выводи ни маркер, ни блок.
    """

    /// Раздел 8.4 ТЗ v1.2: полностью заменяет тело промпта `.plain` для
    /// режима `.dictionary` — не редактируется пользователем (в разделе
    /// 13.3 ТЗ только три редактора: текст/изображение/надстройка, словаря
    /// среди них нет).
    public static let defaultDictionaryTemplate = """
    Пользователь выделил короткий фрагмент — слово или короткую фразу.
    Дай перевод на {targetLanguage} как словарная статья.

    Первой строкой — самый частотный перевод, без пояснений.
    Затем маркер ⟦NOTES⟧, под ним:
    - до трёх альтернативных значений с пометкой контекста в скобках;
    - часть речи и, для {targetLanguage} == русский, род существительных;
    - транслитерация исходного слова русскими буквами, если исходный язык
      использует нелатинскую письменность.

    Каждый пункт — одна строка, начинается с «— ». Без примеров употребления,
    без этимологии, без рассуждений.
    {glossarySection}
    """

    /// Раздел 8.1 ТЗ: `{glossarySection}` подставляется только при непустом глоссарии.
    public static func render(
        template: String,
        targetLanguage: Locale.Language,
        glossary: [String: String]
    ) -> String {
        let languageName = languageDisplayName(targetLanguage)
        let glossarySection = renderGlossarySection(glossary)
        return template
            .replacingOccurrences(of: "{targetLanguage}", with: languageName)
            .replacingOccurrences(of: "{glossarySection}", with: glossarySection)
    }

    /// Раздел 8 ТЗ v1.2: собирает финальный системный промпт по режиму.
    /// `basePromptText` — пользовательский (или дефолтный) промпт `.plain`
    /// для текста или изображения; для `.dictionary` он не используется —
    /// у словарного режима свой фиксированный шаблон (8.4).
    public static func systemPrompt(
        for mode: TranslationMode,
        basePromptText: String,
        notesAddendum: String = defaultNotesAddendum,
        targetLanguage: Locale.Language,
        glossary: [String: String]
    ) -> String {
        switch mode {
        case .plain:
            return render(template: basePromptText, targetLanguage: targetLanguage, glossary: glossary)
        case .withNotes:
            let combined = basePromptText + "\n\n" + notesAddendum
            return render(template: combined, targetLanguage: targetLanguage, glossary: glossary)
        case .dictionary:
            return render(template: defaultDictionaryTemplate, targetLanguage: targetLanguage, glossary: glossary)
        }
    }

    private static func renderGlossarySection(_ glossary: [String: String]) -> String {
        guard !glossary.isEmpty else { return "" }
        let lines = glossary
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "  \($0.key) → \($0.value)" }
            .joined(separator: "\n")
        return "- Обязательная терминология (используй строго эти соответствия):\n\(lines)"
    }

    private static func languageDisplayName(_ language: Locale.Language) -> String {
        Locale(identifier: "ru").localizedString(forLanguageCode: language.languageCode?.identifier ?? language.minimalIdentifier)
            ?? language.minimalIdentifier
    }
}
