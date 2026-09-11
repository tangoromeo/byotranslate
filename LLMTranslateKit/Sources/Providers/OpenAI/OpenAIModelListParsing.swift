import Foundation

/// Раздел 6.4, п. 2 ТЗ: парсинг `GET /models` отдельно от сети — чтобы быть
/// тестируемым без реального запроса.
///
/// Схема достаточно широкая, чтобы покрыть и голый OpenAI API (только
/// `id`), и OpenRouter, который дополнительно отдаёт
/// `architecture.input_modalities` — источник для `ModelDescriptor.supportsImages`,
/// когда он есть, без ручного тумблера от пользователя.
public enum OpenAIModelListParsing {
    struct ListResponse: Decodable {
        struct Model: Decodable {
            let id: String
            let name: String?
            let architecture: Architecture?

            struct Architecture: Decodable {
                let inputModalities: [String]?

                enum CodingKeys: String, CodingKey {
                    case inputModalities = "input_modalities"
                }
            }
        }
        let data: [Model]
    }

    public static func parse(_ data: Data) throws -> [ModelDescriptor] {
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return decoded.data.map { model in
            ModelDescriptor(
                rawID: model.id,
                displayName: model.name,
                supportsImages: model.architecture?.inputModalities.map { $0.contains("image") }
            )
        }
    }
}
