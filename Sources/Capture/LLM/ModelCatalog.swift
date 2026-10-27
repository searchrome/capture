import Foundation

@MainActor
final class ModelCatalog: ObservableObject {
    struct Model: Identifiable {
        let id: String
        let name: String
        let promptPrice: Double
        let completionPrice: Double
        let contextLength: Int?
        var priceDescription: String {
            String(format: "$%.4f / $%.4f per 1M tokens", promptPrice, completionPrice)
        }
    }
    static let shared = ModelCatalog()
    @Published private(set) var models: [Model] = []
    private var loaded = false

    func load(refresh: Bool = false) async throws {
        if loaded && !refresh { return }
        let (data, response) = try await URLSession.shared.data(from: OpenRouterClient.baseURL.appendingPathComponent("models"))
        guard let response = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenRouterError.httpStatus(response.statusCode, nil)
        }
        let entries = try JSONDecoder().decode(Response.self, from: data).data
        models = entries.compactMap { entry in
            guard entry.architecture.inputModalities?.contains("image") == true,
                  let prompt = Double(entry.pricing.prompt), let completion = Double(entry.pricing.completion),
                  prompt >= 0, completion >= 0 else { return nil }
            return Model(id: entry.id, name: entry.name, promptPrice: prompt * 1_000_000,
                         completionPrice: completion * 1_000_000, contextLength: entry.contextLength)
        }.sorted {
            let lhs = $0.promptPrice + $0.completionPrice, rhs = $1.promptPrice + $1.completionPrice
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        loaded = true
    }

    private struct Response: Decodable {
        struct Entry: Decodable {
            struct Architecture: Decodable {
                let inputModalities: [String]?
                enum CodingKeys: String, CodingKey { case inputModalities = "input_modalities" }
            }
            struct Pricing: Decodable { let prompt: String; let completion: String }
            let id: String; let name: String; let architecture: Architecture; let pricing: Pricing; let contextLength: Int?
            enum CodingKeys: String, CodingKey { case id, name, architecture, pricing; case contextLength = "context_length" }
        }
        let data: [Entry]
    }
}
