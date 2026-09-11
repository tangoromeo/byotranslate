import XCTest
@testable import LLMTranslateKit

/// Раздел 6.4, п. 2 ТЗ. Проверяет, что мультимодальность определяется из
/// `architecture.input_modalities` там, где провайдер её публикует
/// (OpenRouter), и остаётся `nil` (решает пользователь) там, где нет
/// (голый OpenAI API).
final class OpenAIModelListParsingTests: XCTestCase {
    func test_plainOpenAIShape_hasNoModalityInfo() throws {
        let json = #"""
        {"data":[{"id":"gpt-4o","object":"model","created":1,"owned_by":"openai"}]}
        """#
        let models = try OpenAIModelListParsing.parse(Data(json.utf8))
        XCTAssertEqual(models, [ModelDescriptor(rawID: "gpt-4o", displayName: nil, supportsImages: nil)])
    }

    func test_openRouterShape_withImageModality_detectsSupport() throws {
        let json = #"""
        {"data":[{"id":"google/gemma-4-31b-it:free","name":"Google: Gemma 4 31B (free)","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}]}
        """#
        let models = try OpenAIModelListParsing.parse(Data(json.utf8))
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].rawID, "google/gemma-4-31b-it:free")
        XCTAssertEqual(models[0].displayName, "Google: Gemma 4 31B (free)")
        XCTAssertEqual(models[0].supportsImages, true)
    }

    func test_openRouterShape_textOnlyModality_detectsNoSupport() throws {
        let json = #"""
        {"data":[{"id":"cohere/north-mini-code:free","architecture":{"input_modalities":["text"],"output_modalities":["text"]}}]}
        """#
        let models = try OpenAIModelListParsing.parse(Data(json.utf8))
        XCTAssertEqual(models[0].supportsImages, false)
    }

    func test_mixedList_eachModelKeepsItsOwnModalityInfo() throws {
        let json = #"""
        {"data":[
            {"id":"gpt-4o"},
            {"id":"vision-model","architecture":{"input_modalities":["text","image"]}},
            {"id":"text-model","architecture":{"input_modalities":["text"]}}
        ]}
        """#
        let models = try OpenAIModelListParsing.parse(Data(json.utf8))
        XCTAssertEqual(models.count, 3)
        XCTAssertNil(models[0].supportsImages)
        XCTAssertEqual(models[1].supportsImages, true)
        XCTAssertEqual(models[2].supportsImages, false)
    }

    func test_malformedJSON_throws() {
        XCTAssertThrowsError(try OpenAIModelListParsing.parse(Data("not json".utf8)))
    }
}
