import XCTest
@testable import LLMTranslateKit

/// B6, этап 3: листы фрагментов и разбор пакетного ответа модели.
final class RegionBatchTests: XCTestCase {
    // MARK: - RegionTranslationParser

    func test_parser_readsPlainJSONArray() {
        let result = RegionTranslationParser.parse(#"[{"n":1,"t":"Выписка"},{"n":2,"t":"Переводы"}]"#)
        XCTAssertEqual(result, [1: "Выписка", 2: "Переводы"])
    }

    func test_parser_toleratesProseAndCodeFenceAroundJSON() {
        let response = "Вот результат:\n```json\n[{\"n\": 3, \"t\": \"Платежи\"}]\n```"
        XCTAssertEqual(RegionTranslationParser.parse(response), [3: "Платежи"])
    }

    func test_parser_acceptsAlternativeKeysAndStringNumbers() {
        let result = RegionTranslationParser.parse(#"[{"id":"1","text":"Счета"},{"number":2,"translation":"Карты"}]"#)
        XCTAssertEqual(result, [1: "Счета", 2: "Карты"])
    }

    func test_parser_acceptsDictionaryByNumber() {
        XCTAssertEqual(RegionTranslationParser.parse(#"{"1":"Счета","2":"Карты"}"#), [1: "Счета", 2: "Карты"])
    }

    func test_parser_fallsBackToNumberedLines() {
        let result = RegionTranslationParser.parse("1. Счета\n2: Карты\n3) Кредиты")
        XCTAssertEqual(result, [1: "Счета", 2: "Карты", 3: "Кредиты"])
    }

    func test_parser_dropsEmptyTranslations() {
        XCTAssertEqual(RegionTranslationParser.parse(#"[{"n":1,"t":"  "},{"n":2,"t":"Да"}]"#), [2: "Да"])
    }

    func test_parser_garbage_returnsEmpty() {
        XCTAssertTrue(RegionTranslationParser.parse("Не могу перевести.").isEmpty)
    }

    func test_parser_keepsQuotesAndUnicodeInsideText() {
        let result = RegionTranslationParser.parse(#"[{"n":1,"t":"«Мои» счета — \"основные\""}]"#)
        XCTAssertEqual(result[1], "«Мои» счета — \"основные\"")
    }

    // MARK: - RegionSheetPlanner

    func test_planner_empty_returnsNoSheets() {
        XCTAssertTrue(RegionSheetPlanner.plan(cropSizes: []).isEmpty)
    }

    func test_planner_fewSmallCrops_fitOneSheet_inOrder() {
        let sheets = RegionSheetPlanner.plan(cropSizes: Array(repeating: CGSize(width: 400, height: 60), count: 5))
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].rows.map(\.index), [0, 1, 2, 3, 4])
        // строки не налезают друг на друга
        let frames = sheets[0].rows.map(\.frame)
        for (upper, lower) in zip(frames, frames.dropFirst()) { XCTAssertLessThanOrEqual(upper.maxY, lower.minY) }
    }

    func test_planner_wideCrop_isScaledDownToMaxWidth_keepingAspect() {
        let sheet = RegionSheetPlanner.plan(cropSizes: [CGSize(width: 1520, height: 200)])[0]
        XCTAssertEqual(sheet.rows[0].frame.width, RegionSheetPlanner.maxCropWidth, accuracy: 1)
        XCTAssertEqual(sheet.rows[0].frame.height, 100, accuracy: 1)
    }

    func test_planner_narrowCrop_isNotUpscaled() {
        let sheet = RegionSheetPlanner.plan(cropSizes: [CGSize(width: 200, height: 40)])[0]
        XCTAssertEqual(sheet.rows[0].frame.size, CGSize(width: 200, height: 40))
    }

    func test_planner_splitsByRowCount() {
        let count = RegionSheetPlanner.maxRowsPerSheet + 3
        let sheets = RegionSheetPlanner.plan(cropSizes: Array(repeating: CGSize(width: 300, height: 30), count: count))
        XCTAssertEqual(sheets.map(\.rows.count), [RegionSheetPlanner.maxRowsPerSheet, 3])
    }

    func test_planner_splitsByHeight_andSheetsStayWithinLimit() {
        let sheets = RegionSheetPlanner.plan(cropSizes: Array(repeating: CGSize(width: 700, height: 400), count: 8))
        XCTAssertGreaterThan(sheets.count, 1)
        for sheet in sheets { XCTAssertLessThanOrEqual(sheet.size.height, RegionSheetPlanner.maxSheetHeight) }
        XCTAssertEqual(sheets.flatMap(\.rows).map(\.index), Array(0..<8))
    }

    func test_planner_tooTallCrop_isShrunkToFitSheet() {
        let sheet = RegionSheetPlanner.plan(cropSizes: [CGSize(width: 500, height: 4000)])[0]
        XCTAssertLessThanOrEqual(sheet.size.height, RegionSheetPlanner.maxSheetHeight)
    }

    func test_planner_capsNumberOfSheets() {
        let count = RegionSheetPlanner.maxRowsPerSheet * (RegionSheetPlanner.maxSheets + 2)
        let sheets = RegionSheetPlanner.plan(cropSizes: Array(repeating: CGSize(width: 300, height: 30), count: count))
        XCTAssertEqual(sheets.count, RegionSheetPlanner.maxSheets)
    }

    func test_planner_skipsDegenerateCropsButKeepsIndices() {
        let sheet = RegionSheetPlanner.plan(cropSizes: [CGSize(width: 300, height: 30), .zero, CGSize(width: 300, height: 30)])[0]
        XCTAssertEqual(sheet.rows.map(\.index), [0, 2])
    }
}
