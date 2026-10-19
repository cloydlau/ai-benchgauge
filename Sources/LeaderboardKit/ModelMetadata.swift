import Foundation

/// Optional model facts from models.dev. Provider prices remain separate and
/// never replace a leaderboard score, rank, developer or publication date.
public struct ModelMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let source: String
    public let sourceURL: String
    public let revision: String
    public let fetchedAt: String
    public let limit: ModelTokenLimits
    public let openWeights: Bool?
    public let license: String?
    public let releaseDate: String?
    public let lastUpdated: String?
    public let offers: [ModelProviderOffer]
    public let attributes: [String: ModelDetailValue]?
}
public struct ModelTokenLimits: Codable, Equatable, Sendable {
    public let context: Int?
    public let input: Int?
    public let output: Int?
}
public struct ModelProviderOffer: Codable, Equatable, Sendable {
    public let provider: String
    public let providerName: String
    public let modelID: String
    public let name: String
    public let limit: ModelTokenLimits
    public let currency: String
    public let unit: String
    public let cost: ModelPricing?
    public let status: String?
    public let attributes: [String: ModelDetailValue]?
}
public struct ModelPriceValues: Codable, Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let reasoning: Double?
    public let cache_read: Double?
    public let cache_write: Double?
    public let input_audio: Double?
    public let output_audio: Double?
}
public struct ModelPricing: Codable, Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let reasoning: Double?
    public let cache_read: Double?
    public let cache_write: Double?
    public let input_audio: Double?
    public let output_audio: Double?
    public let context_over_200k: ModelPriceValues?
    public let tiers: [ModelPriceTier]?
}
public struct ModelPriceTier: Codable, Equatable, Sendable {
    public struct Threshold: Codable, Equatable, Sendable { public let type: String; public let size: Int }
    public let tier: Threshold
    public let input: Double
    public let output: Double
    public let reasoning: Double?
    public let cache_read: Double?
    public let cache_write: Double?
    public let input_audio: Double?
    public let output_audio: Double?
}
public struct ModelMetadataSource: Codable, Equatable, Sendable {
    public let source: String
    public let sourceURL: String
    public let license: String
    public let revision: String
    public let fetchedAt: String
}

/// Bounded public model facts validated by the shared collector. Keeping the
/// JSON types preserves future upstream fields without an app update.
public indirect enum ModelDetailValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([Self]), object([String: Self]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
