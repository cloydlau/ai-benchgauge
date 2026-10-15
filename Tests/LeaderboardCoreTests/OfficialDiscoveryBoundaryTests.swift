import Foundation
import Testing
#if canImport(Security)
import Security
import LocalAuthentication
#endif
@testable import LeaderboardCore

struct OfficialDiscoveryBoundaryTests {
    #if canImport(Security)
    @Test func keychainPolicyNeverNeedsActualUserCredentials() throws {
        for allowed in [true, false] {
            let data = Data("fixture".utf8)
            let actual = OfficialQuotaDiscovery.keychain("unit-\(UUID())", allowsAuthenticationUI: allowed) { query, result in
                let dictionary = query as NSDictionary
                #expect((dictionary[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == !allowed)
                #expect(dictionary[kSecAttrService] as? String != nil)
                result?.pointee = data as CFData
                return errSecSuccess
            }
            #expect(actual == data)
        }
        #expect(OfficialQuotaDiscovery.keychain("unit", allowsAuthenticationUI: false, lookup: { _, _ in errSecItemNotFound }) == nil)
        #expect(OfficialQuotaDiscovery.keychain("unit", allowsAuthenticationUI: false, lookup: { _, output in output?.pointee = "wrong" as CFString; return errSecSuccess }) == nil)
        #expect(OfficialQuotaDiscovery.keychainReader("benchgauge-unit-missing-\(UUID())", false) == nil)
    }
    #endif
    @Test func officialDiscoveryHandlesEveryDocumentedTokenEnvelopeAndHomeOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        for document in [#"{"access_token":"fixture"}"#, #"{"token":{"accessToken":"fixture"}}"#, #"{"main-account":{"access_token":"fixture"}}"#, "{}", "[]", #"{"access_token":"proxy-fixture"}"#] {
            try write("custom/.gemini/oauth_creds.json", document)
            let targets = OfficialQuotaDiscovery.targets(home: root, environment: ["GEMINI_CLI_HOME": root.appendingPathComponent("custom").path], includeKeychain: false)
            #expect(targets.contains(where: { $0.kind == .gemini }) == document.contains("\"fixture\""))
        }
        try write("claude/.credentials.json", #"{"claude.ai_oauth":{"accessToken":"file-token"}}"#)
        let environment = ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("claude").path]
        for included: Set<CCSwitchQuotaKind>? in [nil, [.claude], []] {
            let targets = OfficialQuotaDiscovery.targets(home: root, environment: environment, includeKeychain: true, includedKeychainKinds: included) { service, _ in
                service.contains("Claude") ? Data(#"{"claudeAiOauth":{"accessToken":"keychain-token"}}"#.utf8) : nil
            }
            #expect(targets.first(where: { $0.kind == .claude })?.accessToken == (included?.isEmpty == true ? "file-token" : "keychain-token"))
        }
        try write("kimi/config.toml", """
        [unrelated]
        ignored = 'fixture'
        [providers.good]
        unrelated = 'fixture'
        api_key = 'fixture'
        base_url = 'https://api.kimi.com:443/coding/v1'
        [providers.bad]
        api_key = 'fixture'
        base_url = 'https://user:pass@api.kimi.com/coding/v1'
        [providers.invalid]
        api_key = unquoted
        base_url = 'unterminated
        """)
        let kimi = OfficialQuotaDiscovery.targets(home: root, environment: ["KIMI_HOME": root.appendingPathComponent("kimi").path])
        #expect(kimi.filter { $0.kind == .kimi }.count == 1)
        try write(".codex/auth.json", #"{"tokens":{"access_token":"fixture","account_id":"fixture-account"}}"#)
        #expect(OfficialQuotaDiscovery.targets(home: root, environment: ["CODEX_HOME": root.appendingPathComponent(".codex").path]).contains { $0.accountID == "fixture-account" })
        try write("kimi/credentials/kimi-code.json", #"{"access_token":"oauth-fixture"}"#)
        #expect(OfficialQuotaDiscovery.targets(home: root, environment: ["KIMI_CODE_HOME": root.appendingPathComponent("kimi").path]).contains { $0.accessToken == "oauth-fixture" })
    }
    @Test func saveRejectsOversizedOrUnwritableDocumentsWithoutLeakingTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("accounts")
        #expect(try OfficialQuotaAccountStore(fileURL: url).load().isEmpty)
        let store = OfficialQuotaAccountStore(fileURL: url)
        try Data(repeating: 32, count: 1_048_577).write(to: url)
        #expect(throws: CocoaError.self) { try store.load() }
        #expect(throws: CocoaError.self) { try store.save([], createFile: { _, _ in false }) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["accounts"])
        #expect(OfficialQuotaAccount(providerID: "invalid", label: "", apiKey: "fixture").target == nil)
        #expect(OfficialQuotaAccount(providerID: "deepseek", label: "", apiKey: "fixture\rkey").target == nil)
    }
    @Test func independentKimiAccountsRetainTheirOwnNamesAndNullRoutes() {
        let ids = ["cc-switch:claude:a", "cc-switch:gemini:b", "official-local:kimi:c", "official:d", "cc-switch:unknown:e", "codex-f"]
        let targets = ids.enumerated().map { index, id in CCSwitchQuotaTarget(id: id, shortName: "Kimi", websiteURL: nil, kind: .kimi, isCurrent: false, apiKey: "key-\(index)", baseURL: nil) }
        let merged = OfficialQuotaDiscovery.merge(ccSwitch: targets, official: [])
        #expect(merged.count == ids.count)
        #expect(merged.contains { $0.shortName == "Kimi · Claude Code" })
        #expect(merged.contains { $0.shortName == "Kimi · Gemini CLI" })
        #expect(merged.contains { $0.shortName == "Kimi · Kimi CLI" })
        #expect(merged.contains { $0.shortName == "Kimi 2" })
        let source = CCSwitchQuotaTarget(id: "same", shortName: "Kimi", websiteURL: nil, kind: .kimi, isCurrent: true, apiKey: "key-0", baseURL: nil)
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: [targets[0], source], official: []).count == 1)
    }
    @Test func mergeUsesTheLocalKimiLoginAndKeepsUnrelatedProviders() {
        let selected = CCSwitchQuotaTarget(id: "selected", shortName: "Kimi", websiteURL: nil, kind: .kimi, isCurrent: true, apiKey: nil, baseURL: nil)
        let login = CCSwitchQuotaTarget(id: "official-local:kimi:0", shortName: "Kimi", websiteURL: nil, kind: .kimi, isCurrent: false, apiKey: "fixture", baseURL: "https://api.kimi.com/coding/v1")
        let claude = CCSwitchQuotaTarget(id: "cc-claude", shortName: "Claude", websiteURL: nil, kind: .claude, isCurrent: false, apiKey: nil, baseURL: nil)
        let localClaude = CCSwitchQuotaTarget(id: "official-claude", shortName: "Claude", websiteURL: nil, kind: .claude, isCurrent: false, apiKey: nil, baseURL: nil, accessToken: "fixture")
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: [claude], official: [localClaude]).first?.accessToken == "fixture")
        let other = CCSwitchQuotaTarget(id: "other", shortName: "GLM", websiteURL: nil, kind: .zhipu, isCurrent: false, apiKey: "fixture", baseURL: nil)
        let merged = OfficialQuotaDiscovery.merge(ccSwitch: [other, selected], official: [login, other, localClaude])
        #expect(merged.first(where: { $0.id == "selected" })?.apiKey == "fixture")
        #expect(merged.first(where: { $0.id == "selected" })?.baseURL == login.baseURL)
    }

}


extension OfficialDiscoveryBoundaryTests {
    @Test func fresherExactAccountTokensReplaceMissingOrMalformedExpiryHints() {
        func target(_ token: String?, id: String = "selected") -> CCSwitchQuotaTarget {
            .init(id: id, shortName: "OpenAI", websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil, accessToken: token, accountID: "fixture")
        }
        let fresh = "header." + Data(#"{"exp":2000000000}"#.utf8).base64EncodedString() + ".signature"
        let invalidPayload = "header." + Data("not JSON".utf8).base64EncodedString() + ".signature"
        let noExpiry = "header." + Data("{}".utf8).base64EncodedString() + ".signature"
        for old in [nil, "", "a.invalid.c", invalidPayload, noExpiry] {
            let merged = OfficialQuotaDiscovery.merge(ccSwitch: [target(old)], official: [target(fresh, id: "official-local:openai")], now: Date(timeIntervalSince1970: 1900000000))
            #expect(merged.first?.id == "selected")
            #expect(merged.first?.accessToken == fresh)
        }
    }
}
