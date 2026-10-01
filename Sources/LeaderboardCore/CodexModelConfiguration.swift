import LeaderboardKit
import Foundation

/// Optional display metadata from the live Codex configuration. Never reads auth.json
/// or changes the credentials used to query a CC Switch provider's quota.
public struct CodexModelConfiguration: Equatable, Sendable {
    public let model: String
    public let provider: String?
    public let baseURL: String?

    public init(model: String, provider: String? = nil, baseURL: String? = nil) {
        self.model = model
        self.provider = provider
        self.baseURL = baseURL
    }

    public static func load(from url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let config = String(data: data, encoding: .utf8) else { return nil }
        return parse(config)
    }

    public static func parse(_ config: String) -> Self? {
        var section = ""
        var root: [String: String] = [:]
        var urls: [String: String] = [:]
        for raw in config.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                guard let end = line.firstIndex(of: "]") else { return nil }
                section = String(line[line.index(after: line.startIndex)..<end])
                continue
            }
            guard let equal = line.firstIndex(of: "=") else { continue }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            let relevant = section.isEmpty ? ["model", "model_provider"].contains(key)
                : section.hasPrefix("model_providers.") && key == "base_url"
            guard relevant else { continue }
            guard let value = quotedValue(String(line[line.index(after: equal)...])) else { return nil }
            if section.isEmpty { root[key] = value }
            else {
                let name = String(section.dropFirst("model_providers.".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                urls[name] = value
            }
        }
        guard let model = root["model"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty, model.count <= 128 else { return nil }
        let provider = root["model_provider"]
        return Self(model: model, provider: provider, baseURL: provider.flatMap { urls[$0] })
    }

    /// A live OpenAI model must not rename a Kimi/Grok/GLM provider, or vice versa.
    public func modelName(matching target: CCSwitchQuotaTarget) -> String? {
        guard target.isCurrent else { return nil }
        if provider == nil || provider == "openai" {
            return target.kind == .officialNote ? model : nil
        }
        guard target.kind != .officialNote, let baseURL, let targetURL = target.baseURL,
              normalizedURL(baseURL) == normalizedURL(targetURL) else { return nil }
        return model
    }

    private func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func quotedValue(_ source: String) -> String? {
        let text = source.trimmingCharacters(in: .whitespaces)
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        var escaped = false
        for index in text.indices.dropFirst() {
            let character = text[index]
            if quote == "\"", character == "\\", !escaped { escaped = true; continue }
            if character == quote, !escaped {
                let remainder = text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
                guard remainder.isEmpty || remainder.hasPrefix("#") else { return nil }
                let quoted = String(text[...index])
                if quote == "'" { return String(quoted.dropFirst().dropLast()) }
                return (try? JSONSerialization.jsonObject(with: Data(quoted.utf8), options: .fragmentsAllowed)) as? String
            }
            escaped = false
        }
        return nil
    }
}
