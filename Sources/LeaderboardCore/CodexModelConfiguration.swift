import LeaderboardKit
import Foundation

/// Optional display metadata from Codex sessions/configuration. Never reads auth.json
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
        parse(config, session: nil)
    }

    /// Session model/provider take precedence. Resolve only that provider's URL;
    /// never attach the default provider's route to an unrelated session.
    static func load(from url: URL, session: Self) -> Self {
        guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let config = String(data: data, encoding: .utf8) else { return session }
        return parse(config, session: session) ?? session
    }

    private static func parse(_ config: String, session: Self?) -> Self? {
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
        guard let model = (session?.model ?? root["model"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty, model.count <= 128 else { return nil }
        let provider = session?.provider ?? root["model_provider"]
        return Self(model: model, provider: provider, baseURL: provider.flatMap { urls[$0] })
    }

    /// Resolve the active quota source from live routing metadata, not a stale
    /// CC Switch selection. A loopback proxy hides its upstream URL, so only an
    /// exact, unique saved model match may identify the account behind it.
    public func selectingCurrentTarget(in targets: [CCSwitchQuotaTarget]) -> [CCSwitchQuotaTarget] {
        let matches = targets.filter { matchesRoute(to: $0) }
        let selected: CCSwitchQuotaTarget?
        if isLoopbackProxy {
            selected = matches.count == 1 ? matches.first : nil
        } else {
            let current = matches.filter(\.isCurrent)
            selected = current.count == 1 ? current.first : matches.count == 1 ? matches.first : nil
        }
        return targets.map { target in
            CCSwitchQuotaTarget(id: target.id, shortName: target.shortName, modelName: target.modelName,
                websiteURL: target.websiteURL, kind: target.kind, isCurrent: target.id == selected?.id,
                apiKey: target.apiKey, baseURL: target.baseURL, accessToken: target.accessToken, accountID: target.accountID)
        }
    }

    /// Project both the model label and its account's quota together. If the
    /// route is ambiguous/unknown, retain the live model without another
    /// provider's amount. Query credentials are never replaced here.
    public func menuBarText(for chips: [AccountQuotaChip], targets: [CCSwitchQuotaTarget]) -> AccountQuotaMenuBarText? {
        let selectedID = selectingCurrentTarget(in: targets).first(where: \.isCurrent)?.id
        let display = chips.map { chip in
            AccountQuotaChip(id: chip.id, shortName: chip.shortName, modelName: chip.modelName,
                websiteURL: chip.websiteURL, kind: chip.kind, isCurrent: chip.id == selectedID,
                status: chip.status, isStale: chip.isStale)
        }
        return AccountQuotaFormatting.menuBarText(forChips: display, currentModelName: model)
    }

    /// A live OpenAI model must not rename a Kimi/Grok/GLM provider, or vice versa.
    public func modelName(matching target: CCSwitchQuotaTarget) -> String? {
        target.isCurrent && matchesRoute(to: target) ? model : nil
    }

    private var isLoopbackProxy: Bool {
        guard provider != nil, provider != "openai", let baseURL, let url = URL(string: baseURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
    }

    private func matchesRoute(to target: CCSwitchQuotaTarget) -> Bool {
        if provider == nil || provider == "openai" { return target.kind == .officialNote }
        if isLoopbackProxy { return target.modelName == model }
        guard target.kind != .officialNote, let baseURL, let targetURL = target.baseURL else { return false }
        return normalizedURL(baseURL) == normalizedURL(targetURL)
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
