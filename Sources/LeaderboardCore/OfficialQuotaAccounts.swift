import Foundation
#if canImport(Security)
import Security
import LocalAuthentication
#endif

public struct OfficialQuotaAccount: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public let label: String
    // Persisted only in the user's private account configuration; never in DTOs.
    private let apiKey: String

    public init(id: String = "official:\(UUID().uuidString)", providerID: String, label: String, apiKey: String) {
        self.id = id; self.providerID = providerID; self.label = label; self.apiKey = apiKey
    }

    public var target: CCSwitchQuotaTarget? {
        guard let provider = LeaderboardQuotaProviders.keyProviders.first(where: { $0.id == providerID }),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              apiKey.utf8.count <= 16_384,
              !apiKey.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else { return nil }
        return CCSwitchQuotaTarget(id: id, shortName: provider.name + (label.isEmpty ? "" : " · \(label)"),
                                  websiteURL: provider.websiteURL, kind: provider.kind, isCurrent: false,
                                  apiKey: apiKey, baseURL: provider.baseURL)
    }
}

public struct OfficialQuotaAccountStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL = PlatformPaths.applicationSupport.appending(path: "official-quota-accounts.json")) {
        self.fileURL = fileURL
    }

    public func load() throws -> [OfficialQuotaAccount] {
        guard FileManager.default.fileExists(atPath: PlatformPaths.fileSystemPath(fileURL)) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode([OfficialQuotaAccount].self, from: data)
    }

    public func save(_ accounts: [OfficialQuotaAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".quota-accounts-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Set private permissions before writing any credential bytes.
        #if os(Windows)
        let attributes: [FileAttributeKey: Any] = [:]
        #else
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #endif
        guard FileManager.default.createFile(atPath: PlatformPaths.fileSystemPath(temporary), contents: nil,
                                            attributes: attributes) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: temporary)
        if FileManager.default.fileExists(atPath: PlatformPaths.fileSystemPath(fileURL)) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        #endif
    }
}

public enum ClaudeKeychainConsent: String, Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

public enum ClaudeKeychainConsentPreference {
    public static let userDefaultsKey = "AIBenchGauge.claudeKeychainConsent"

    public static func load(from defaults: UserDefaults = .standard) -> ClaudeKeychainConsent {
        guard let raw = defaults.string(forKey: userDefaultsKey) else { return .notDetermined }
        return ClaudeKeychainConsent(rawValue: raw) ?? .notDetermined
    }

    public static func save(_ consent: ClaudeKeychainConsent, to defaults: UserDefaults = .standard) {
        defaults.set(consent.rawValue, forKey: userDefaultsKey)
    }
}

/// Explicit official locations only. Never scan arbitrary files, shells, or
/// browser profiles. Refresh tokens remain owned by the official clients.
public enum OfficialQuotaDiscovery {
    public static func targets(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               includeKeychain: Bool = false,
                               allowKeychainAuthenticationUI: Bool = false,
                               includedKeychainKinds: Set<CCSwitchQuotaKind>? = nil) -> [CCSwitchQuotaTarget] {
        var targets: [CCSwitchQuotaTarget] = []
        for (kind, directory, file, service) in [
            (CCSwitchQuotaKind.claude, ".claude", ".credentials.json", "Claude Code-credentials"),
            (.gemini, ".gemini", "oauth_creds.json", "gemini-cli-oauth"),
        ] {
            let configured = kind == .claude ? environment["CLAUDE_CONFIG_DIR"] : environment["GEMINI_CLI_HOME"]
            let configuredRoot = configured.map { URL(fileURLWithPath: $0) }
            // GEMINI_CLI_HOME replaces the home directory, while
            // CLAUDE_CONFIG_DIR is the actual configuration directory.
            let root = kind == .gemini ? (configuredRoot ?? home).appending(path: directory)
                : (configuredRoot ?? home.appending(path: directory))
            let usesKeychain = includeKeychain && (includedKeychainKinds?.contains(kind) ?? true)
            let token = (usesKeychain
                ? keychain(service, allowsAuthenticationUI: allowKeychainAuthenticationUI)
                    .flatMap { oauthToken($0, kind: kind) }
                : nil)
                ?? read(root.appending(path: file)).flatMap { oauthToken($0, kind: kind) }
            guard let token else { continue }
            targets.append(CCSwitchQuotaTarget(id: "official-local:\(kind.rawValue)",
                shortName: kind == .claude ? "Claude" : "Gemini",
                websiteURL: URL(string: kind == .claude ? "https://claude.ai/settings/usage" : "https://gemini.google.com"),
                kind: kind, isCurrent: false, apiKey: nil, baseURL: nil, accessToken: token))
        }

        let codexRoot = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appending(path: ".codex")
        if let data = read(codexRoot.appending(path: "auth.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = object["tokens"] as? [String: Any], let access = usable(tokens["access_token"] as? String) {
            targets.append(CCSwitchQuotaTarget(id: "official-local:openai", shortName: "OpenAI",
                websiteURL: URL(string: "https://chatgpt.com/codex/settings/usage"), kind: .officialNote,
                isCurrent: false, apiKey: nil, baseURL: nil, accessToken: access, accountID: tokens["account_id"] as? String))
        }

        var roots = [home.appending(path: ".kimi-code"), home.appending(path: ".kimi")]
        if let override = environment["KIMI_CODE_HOME"] ?? environment["KIMI_HOME"] { roots.insert(URL(fileURLWithPath: override), at: 0) }
        for (index, root) in roots.enumerated() {
            if let data = read(root.appending(path: "credentials/kimi-code.json")),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = usable(object["access_token"] as? String) {
                targets.append(CCSwitchQuotaTarget(id: "official-local:kimi:\(index)", shortName: "Kimi",
                    websiteURL: URL(string: "https://www.kimi.com/code"), kind: .kimi,
                    isCurrent: false, apiKey: nil, baseURL: "https://api.kimi.com/coding/v1", accessToken: token))
                break
            }
            guard let data = read(root.appending(path: "config.toml")), let config = String(data: data, encoding: .utf8) else { continue }
            for (provider, fields) in kimiProviderFields(config).sorted(by: { $0.key < $1.key }) {
                guard let key = usable(fields["api_key"]), let base = fields["base_url"],
                      let url = URL(string: base), url.scheme == "https", url.host == "api.kimi.com",
                      url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                      url.path.hasPrefix("/coding/") else { continue }
                targets.append(CCSwitchQuotaTarget(id: "official-local:kimi:\(index):\(provider)", shortName: "Kimi",
                    websiteURL: URL(string: "https://www.kimi.com/code"), kind: .kimi,
                    isCurrent: false, apiKey: key, baseURL: base))
            }
        }
        return targets
    }

    public static func merge(ccSwitch: [CCSwitchQuotaTarget], official: [CCSwitchQuotaTarget], now: Date = Date()) -> [CCSwitchQuotaTarget] {
        // Identity is a credential/account, not merely a provider name.
        var remaining = official
        var result = ccSwitch.map { target in
            // Codex renews its own login while CC Switch keeps a saved snapshot.
            // Use a newer, unexpired token only for the exact same account;
            // retain the selected provider's ID and display metadata.
            if target.kind == .officialNote, let accountID = target.accountID, !accountID.isEmpty,
               let login = official.first(where: {
                   $0.id == "official-local:openai" && $0.kind == .officialNote && $0.accountID == accountID
               }), let expiry = tokenExpiry(login.accessToken), expiry > now,
               tokenExpiry(target.accessToken).map({ expiry > $0 }) ?? true {
                return CCSwitchQuotaTarget(id: target.id, shortName: target.shortName, modelName: target.modelName,
                    websiteURL: target.websiteURL ?? login.websiteURL, kind: target.kind, isCurrent: target.isCurrent,
                    apiKey: target.apiKey, baseURL: target.baseURL, accessToken: login.accessToken, accountID: accountID)
            }
            let usesLocalLogin = [.claude, .gemini].contains(target.kind)
                || (target.kind == .kimi && usable(target.apiKey) == nil)
            guard usesLocalLogin, target.accessToken == nil,
                  let index = remaining.firstIndex(where: { $0.kind == target.kind }) else { return target }
            let login = remaining.remove(at: index)
            return CCSwitchQuotaTarget(id: target.id, shortName: target.shortName, modelName: target.modelName,
                websiteURL: target.websiteURL ?? login.websiteURL, kind: target.kind, isCurrent: target.isCurrent,
                apiKey: target.kind == .kimi ? login.apiKey : nil,
                baseURL: target.kind == .kimi ? (target.baseURL ?? login.baseURL) : nil,
                accessToken: login.accessToken)
        }
        for target in remaining {
            let duplicate = result.contains { existing in
                guard existing.kind == target.kind else { return false }
                if let id = target.accountID, !id.isEmpty, existing.accountID == id { return true }
                let sameRegion = URL(string: existing.baseURL ?? "")?.host == URL(string: target.baseURL ?? "")?.host
                return (target.accessToken != nil && existing.accessToken == target.accessToken)
                    || (sameRegion && target.apiKey != nil && existing.apiKey == target.apiKey)
            }
            if !duplicate { result.append(target) }
        }
        return mergeKimiSources(result)
    }

    /// A configured Kimi key is the quota source; automatic CLI OAuth discovery
    /// is a fallback. It can contain an old login unrelated to the current key.
    /// Explicit accounts with different keys remain independent.
    private static func mergeKimiSources(_ targets: [CCSwitchQuotaTarget]) -> [CCSwitchQuotaTarget] {
        let hasConfiguredKey = targets.contains { $0.kind == .kimi && usable($0.apiKey) != nil }
        var result: [CCSwitchQuotaTarget] = []
        for target in targets {
            if hasConfiguredKey && target.kind == .kimi && target.id.hasPrefix("official-local:kimi:")
                && target.accessToken != nil && usable(target.apiKey) == nil { continue }
            if target.kind == .kimi, let key = usable(target.apiKey),
               let index = result.firstIndex(where: {
                   $0.kind == .kimi && usable($0.apiKey) == key
                       && URL(string: $0.baseURL ?? "")?.host?.lowercased()
                           == URL(string: target.baseURL ?? "")?.host?.lowercased()
               }) {
                // Preserve the current provider's ID and concrete model when
                // OpenCode and Codex use the same credential.
                if target.isCurrent { result[index] = target }
            } else { result.append(target) }
        }
        // The CC Switch catalog numbered names before sources were merged.
        // Renumber its remaining Kimi entries so a lone account is simply Kimi.
        let multipleKimi = result.filter { $0.kind == .kimi }.count > 1
        var seenNames: [String: Int] = [:]
        return result.map { target in
            guard target.kind == .kimi,
                  target.shortName == "Kimi" || target.shortName.range(of: #"^Kimi \d+$"#, options: .regularExpression) != nil else { return target }
            let source: String?
            if target.id.hasPrefix("cc-switch:opencode:") { source = "OpenCode" }
            else if target.id.hasPrefix("cc-switch:claude:") { source = "Claude Code" }
            else if target.id.hasPrefix("cc-switch:gemini:") { source = "Gemini CLI" }
            else if target.id.hasPrefix("official-local:kimi:") { source = "Kimi CLI" }
            else if !target.id.hasPrefix("official:") && !target.id.hasPrefix("cc-switch:") { source = "Codex" }
            else { source = nil }
            let name = multipleKimi ? source.map { "Kimi · \($0)" } ?? "Kimi" : "Kimi"
            let count = seenNames[name, default: 0] + 1
            seenNames[name] = count
            return CCSwitchQuotaTarget(id: target.id, shortName: count == 1 ? name : "\(name) \(count)",
                modelName: target.modelName, websiteURL: target.websiteURL, kind: target.kind,
                isCurrent: target.isCurrent, apiKey: target.apiKey, baseURL: target.baseURL,
                accessToken: target.accessToken, accountID: target.accountID)
        }
    }

    /// JWT expiry is only a freshness hint. Account matching above controls
    /// which saved login may replace the snapshot; the server validates tokens.
    private static func tokenExpiry(_ token: String?) -> Date? {
        guard let token = usable(token) else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = object["exp"] as? Double, expiry.isFinite else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    private static func read(_ url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1_048_576 else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func oauthToken(_ data: Data, kind: CCSwitchQuotaKind) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if kind == .claude {
            let entry = (object["claudeAiOauth"] ?? object["claude.ai_oauth"]) as? [String: Any]
            return usable(entry?["accessToken"] as? String)
        }
        if let token = usable(object["access_token"] as? String) { return token }
        if let entry = object["token"] as? [String: Any], let token = usable(entry["accessToken"] as? String) { return token }
        let entry = object["main-account"] as? [String: Any]
        return usable(entry?["access_token"] as? String)
    }

    private static func usable(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("proxy-"), value.utf8.count <= 16_384,
              !value.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else { return nil }
        return value
    }

    private static func keychain(_ service: String, allowsAuthenticationUI: Bool) -> Data? {
        #if canImport(Security)
        var result: CFTypeRef?
        // Only an explicit consent-triggered refresh may summon macOS' dialog.
        let context = LAContext()
        context.interactionNotAllowed = !allowsAuthenticationUI
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
        #else
        return nil
        #endif
    }

    private static func kimiProviderFields(_ config: String) -> [String: [String: String]] {
        var section: String?
        var result: [String: [String: String]] = [:]
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.hasPrefix("[providers.") && line.hasSuffix("]") ? String(line.dropFirst(11).dropLast()) : nil
            } else if let section, let equals = line.firstIndex(of: "=") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                guard ["api_key", "base_url"].contains(key) else { continue }
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                guard let quote = value.first, quote == "\"" || quote == "'",
                      let end = value.dropFirst().firstIndex(of: quote) else { continue }
                result[section, default: [:]][key] = String(value[value.index(after: value.startIndex)..<end])
            }
        }
        return result
    }
}
