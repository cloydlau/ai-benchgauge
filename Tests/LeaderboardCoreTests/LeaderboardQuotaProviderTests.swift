import Foundation
import LeaderboardCore
import CSQLite
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct LeaderboardQuotaProviderTests {
    @Test func priorityUsesBothSourcesOfEveryCategory() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "fixtures/quota-priority-2026-10-01.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LeaderboardSnapshot.self, from: Data(contentsOf: file))
        #expect(snapshot.boards.count == 8)
        #expect(LeaderboardCategory.allCases.allSatisfy { $0.boardKinds.allSatisfy { snapshot.boards[$0]?.entries.count == 20 } })
        let organizations = LeaderboardQuotaProviders.rankedOrganizations(in: snapshot)
        #expect(organizations.contains("minimax")) // video only in this snapshot
        #expect(organizations.contains("luma")) // Arena image only
        #expect(organizations.contains("ideogram"))
        #expect(organizations.contains("blackforestlabs"))
        #expect(LeaderboardQuotaProviders.keyProviders.allSatisfy { organizations.contains($0.organizationKey) })
        #expect(!LeaderboardQuotaProviders.keyProviders.contains { ["siliconflow", "openrouter", "novita"].contains($0.id) })
        let generalOnly = LeaderboardSnapshot(boards: snapshot.boards.filter { LeaderboardCategory.general.boardKinds.contains($0.key) })
        #expect(!LeaderboardQuotaProviders.rankedOrganizations(in: generalOnly).contains("luma"))
    }

    @Test func miniMaxSelectsCodingAndHonorsOptionalWeeklyWindow() {
        let json = #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"video","current_interval_remaining_percent":0},{"model_name":"general","current_interval_remaining_percent":80,"end_time":1790800000000,"current_weekly_status":1,"current_weekly_remaining_percent":25,"weekly_end_time":1790900000000}]}"#
        guard case let .windows(windows) = LeaderboardQuotaParsers.miniMax(Data(json.utf8)) else { Issue.record("Missing Coding Plan windows"); return }
        #expect(windows.map(\.utilization) == [20, 75])
        #expect(windows.map(\.name) == ["five_hour", "weekly_limit"])
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1790800000))
        let noWeekly = json.replacingOccurrences(of: "\"current_weekly_status\":1", with: "\"current_weekly_status\":3")
        guard case let .windows(one) = LeaderboardQuotaParsers.miniMax(Data(noWeekly.utf8)) else { Issue.record("Missing 5h"); return }
        #expect(one.count == 1)
        #expect(LeaderboardQuotaParsers.miniMax(Data(#"{"base_resp":{"status_code":1004},"model_remains":[]}"#.utf8)) == .rejected)
        #expect(LeaderboardQuotaParsers.miniMax(Data(#"{"model_remains":[{"model_name":"video","current_interval_remaining_percent":100}]}"#.utf8)) == .rejected)
    }

    @Test func creditUnitsArePreservedAndMissingValuesAreRejected() {
        #expect(LeaderboardQuotaParsers.luma(Data(#"{"credit_balance":1234}"#.utf8)) == .balances([ParsedBalance(currency: "USD", amount: 12.34)]))
        #expect(LeaderboardQuotaParsers.blackForestLabs(Data(#"{"credits":345}"#.utf8)) == .balances([ParsedBalance(currency: "credits", amount: 345)]))
        #expect(LeaderboardQuotaParsers.stepFun(Data(#"{"balance":0}"#.utf8)) == .balances([ParsedBalance(currency: "CNY", amount: 0)]))
        #expect(LeaderboardQuotaParsers.stepFun(Data(#"{"balance":1}"#.utf8)) == .balances([ParsedBalance(currency: "CNY", amount: 1)]))
        for json in [#"{}"#, #"{"balance":true}"#, #"{"balance":-1}"#, #"{"balance":"nan"}"#, #"{"balance":4,"error":"bad key"}"#] {
            #expect(LeaderboardQuotaParsers.stepFun(Data(json.utf8)) == .rejected)
        }
    }

    @Test func officialSubscriptionParsersDoNotInventMissingQuota() {
        let claude = LeaderboardQuotaParsers.claude(Data(#"{"five_hour":{"utilization":5,"resets_at":"2026-10-02T01:00:00Z"},"seven_day":{"utilization":50},"extra_usage":{"utilization":95}}"#.utf8))
        guard case let .windows(windows) = claude else { Issue.record("Missing subscription windows"); return }
        #expect(windows.map(\.name) == ["five_hour", "seven_day"])
        let gemini = LeaderboardQuotaParsers.gemini(Data(#"{"buckets":[{"modelId":"gemini-3-pro","remainingFraction":0.8},{"modelId":"gemini-3.1-pro","remainingFraction":0.4},{"modelId":"gemini-flash","remainingFraction":0},{"modelId":"gemini-flash-lite","remainingFraction":true},{"modelId":"unreported"}]}"#.utf8))
        guard case let .windows(buckets) = gemini else { Issue.record("Missing quota buckets"); return }
        #expect(buckets.count == 2)
        #expect(buckets.first(where: { $0.name == "gemini_pro" })?.utilization == 60)
        #expect(buckets.first(where: { $0.name == "gemini_flash" })?.utilization == 100)
        #expect(LeaderboardQuotaParsers.gemini(Data(#"{"buckets":[{"modelId":"gemini-pro"}]}"#.utf8)) == .rejected)
    }

    @Test func onlyOfficialHostsAreRecognized() {
        #expect(LeaderboardQuotaProviders.kind(forBaseURL: "https://api.minimax.cn/anthropic") == .minimax)
        #expect(LeaderboardQuotaProviders.kind(forBaseURL: "https://api.lumalabs.ai/dream-machine/v1") == .luma)
        for url in ["https://api.minimax.io.evil.test", "https://evil.test/api.bfl.ai", "http://api.bfl.ai", "https://user@api.bfl.ai", "https://api.bfl.ai:8443"] {
            #expect(LeaderboardQuotaProviders.kind(forBaseURL: url) == nil)
        }
    }

    @Test func ccSwitchTemplatesAndQueryCredentialOverrideWork() {
        let settings = #"{"env":{"ANTHROPIC_AUTH_TOKEN":"inference-key","ANTHROPIC_BASE_URL":"https://api.minimaxi.com/anthropic"}}"#
        let meta = #"{"usage_script":{"enabled":true,"templateType":"token_plan","codingPlanProvider":"minimax","apiKey":"query-key"}}"#
        let record = CCSwitchProviderRecord(id: "cc-switch:claude:test", name: "MiniMax", websiteURL: nil, sortIndex: nil,
            createdAt: 0, isCurrent: false, metaJSON: meta, settingsConfigJSON: settings)
        let targets = CCSwitchQuotaCatalog.targets(from: [record], currentProviderID: nil)
        #expect(targets.count == 1)
        #expect(targets.first?.kind == .minimax)
        #expect(targets.first?.apiKey == "query-key")
        let disabled = CCSwitchProviderRecord(id: record.id, name: record.name, websiteURL: nil, sortIndex: nil, createdAt: 0,
            isCurrent: false, metaJSON: meta.replacingOccurrences(of: "true", with: "false"), settingsConfigJSON: settings)
        #expect(CCSwitchQuotaCatalog.targets(from: [disabled], currentProviderID: nil).isEmpty)
        let overrides = CCSwitchProviderRecord(id: record.id, name: record.name, websiteURL: nil, sortIndex: nil,
            createdAt: 0, isCurrent: false,
            metaJSON: #"{"usage_script":{"enabled":true,"templateType":"token_plan","codingPlanProvider":"minimax","apiKey":"query-key","baseUrl":"https://api.minimax.io"}}"#,
            settingsConfigJSON: settings.replacingOccurrences(of: "https://api.minimaxi.com/anthropic", with: "https://proxy.example"))
        #expect(CCSwitchQuotaCatalog.targets(from: [overrides], currentProviderID: nil).first?.baseURL == "https://api.minimax.io")
        let custom = CCSwitchProviderRecord(id: record.id, name: record.name, websiteURL: nil, sortIndex: nil,
            createdAt: 0, isCurrent: false, metaJSON: meta.replacingOccurrences(of: "token_plan", with: "custom"), settingsConfigJSON: settings)
        #expect(CCSwitchQuotaCatalog.targets(from: [custom], currentProviderID: nil).isEmpty)
    }

    @Test func requestsUseCorrectAuthAndRegionalOfficialEndpoints() async throws {
        for provider in LeaderboardQuotaProviders.keyProviders.filter({ [.minimax, .stepfun, .blackForestLabs, .luma].contains($0.kind) }) {
            let body: String
            switch provider.kind {
            case .minimax: body = #"{"model_remains":[{"model_name":"general","current_interval_remaining_percent":90}]}"#
            case .stepfun: body = #"{"balance":1}"#
            case .blackForestLabs: body = #"{"credits":100}"#
            default: body = #"{"credit_balance":100}"#
            }
            let transport = QuotaProviderTestTransport(bodies: [body])
            let account = OfficialQuotaAccount(providerID: provider.id, label: "", apiKey: "fake-key")
            let target = try #require(account.target)
            let chips = try await AccountQuotaClient(transport: transport).refresh(targets: [target])
            #expect(chips.count == 1)
            #expect(chips.first?.status != .message(AccountQuotaMessage.queryFailed))
            let requests = await transport.requests
            let request = try #require(requests.first)
            if provider.kind == .blackForestLabs {
                #expect(request.value(forHTTPHeaderField: "x-key") == "fake-key")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            } else { #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key") }
            if provider.kind == .minimax {
                #expect(request.url?.host == (provider.id == "minimax-global" ? "api.minimax.io" : "api.minimaxi.com"))
                #expect(request.url?.path == "/v1/api/openplatform/coding_plan/remains")
            }
        }
    }

    @Test func geminiCarriesProjectFromFirstRequestIntoQuotaRequest() async throws {
        let transport = QuotaProviderTestTransport(bodies: [#"{"cloudaicompanionProject":{"id":"test-project"}}"#,
            #"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.5}]}"#])
        let target = CCSwitchQuotaTarget(id: "gemini", shortName: "Gemini", websiteURL: nil, kind: .gemini,
            isCurrent: false, apiKey: nil, baseURL: nil, accessToken: "fake-oauth-token")
        let chips = try await AccountQuotaClient(transport: transport).refresh(targets: [target])
        guard case let .windows(windows) = chips.first?.status else { Issue.record("Query failed"); return }
        #expect(windows.first?.utilization == 50)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        let body = try JSONSerialization.jsonObject(with: #require(requests[1].httpBody)) as? [String: String]
        #expect(body?["project"] == "test-project")
    }

    @Test func expiredOAuthIsReauthAndAPIKeysAreNeverSentToSubscriptionEndpoints() async throws {
        let transport = QuotaProviderTestTransport(bodies: ["{}"], status: 401)
        let target = CCSwitchQuotaTarget(id: "claude", shortName: "Claude", websiteURL: nil, kind: .claude,
            isCurrent: false, apiKey: "must-not-be-sent", baseURL: nil, accessToken: "fake-expired-token")
        let client = AccountQuotaClient(transport: transport)
        #expect(try await client.refresh(targets: [target]).first?.status == .message(AccountQuotaMessage.reauthRequired))
        let noLogin = CCSwitchQuotaTarget(id: "missing", shortName: "Claude", websiteURL: nil, kind: .claude,
            isCurrent: false, apiKey: "must-not-be-sent", baseURL: nil)
        #expect(try await client.refresh(targets: [noLogin]).first?.status == .note(text: AccountQuotaMessage.notConfigured, help: AccountQuotaMessage.notConfiguredHelp))
        #expect(await transport.requests.count == 1)
    }

    @Test func officialDetectionUsesKnownFilesWithoutCCSwitchAndPreservesThem() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let files = [".claude/.credentials.json": #"{"claudeAiOauth":{"accessToken":"fake-claude"}}"#,
            ".gemini/oauth_creds.json": #"{"access_token":"fake-gemini"}"#,
            ".codex/auth.json": #"{"tokens":{"access_token":"fake-codex","account_id":"fake-account"}}"#,
            ".kimi/config.toml": "[providers.kimi]\nbase_url = \"https://api.kimi.com/coding/v1\"\napi_key = \"fake-kimi-key\"\n[providers.other]\nbase_url = \"https://proxy.example/coding/v1\"\napi_key = \"do-not-query\"\n"]
        for (file, value) in files { try write(value, root.appending(path: file)) }
        let targets = OfficialQuotaDiscovery.targets(home: root, environment: [:], includeKeychain: false)
        #expect(targets.map(\.kind) == [.claude, .gemini, .officialNote, .kimi])
        #expect(targets.last?.apiKey == "fake-kimi-key")
        #expect(targets.allSatisfy { !$0.isCurrent })
        for (file, value) in files { #expect(try String(contentsOf: root.appending(path: file), encoding: .utf8) == value) }
        let customHome = root.appending(path: "gemini-home")
        try write(#"{"access_token":"fake-custom-gemini"}"#, customHome.appending(path: ".gemini/oauth_creds.json"))
        let overridden = OfficialQuotaDiscovery.targets(home: root,
            environment: ["GEMINI_CLI_HOME": customHome.path], includeKeychain: false)
        #expect(overridden.first(where: { $0.kind == .gemini })?.accessToken == "fake-custom-gemini")
    }

    @Test func officialAccountsPersistPrivatelyAndSameProviderAccountsStayDistinct() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = OfficialQuotaAccountStore(fileURL: root.appending(path: "accounts.json"))
        let first = OfficialQuotaAccount(providerID: "luma", label: "first", apiKey: "fake-one")
        let second = OfficialQuotaAccount(providerID: "luma", label: "second", apiKey: "fake-two")
        try store.save([first, second]); #expect(try store.load() == [first, second])
        try store.save([second]); #expect(try store.load() == [second])
        #if !os(Windows)
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #endif
        let merged = OfficialQuotaDiscovery.merge(ccSwitch: [try #require(first.target)], official: [try #require(first.target), try #require(second.target)])
        #expect(merged.map(\.id) == [first.id, second.id])
        #expect(OfficialQuotaAccount(providerID: "openrouter", label: "", apiKey: "fake-key").target == nil)
        #expect(OfficialQuotaAccount(providerID: "kimi", label: "", apiKey: "fake\r\nkey").target == nil)
    }

    @Test func kimiOpenCodeAndCodexShareOneQuotaAndLocalOAuthIsFallback() async throws {
        let openCode = CCSwitchProviderRecord(id: "cc-switch:opencode:kimi", name: "Kimi", websiteURL: nil,
            sortIndex: 0, createdAt: 0, isCurrent: false, metaJSON: "{}",
            settingsConfigJSON: #"{"options":{"baseURL":"https://api.kimi.com/coding/v1","apiKey":"fake-kimi-key"}}"#)
        let codex = CCSwitchProviderRecord(id: "kimi-codex", name: "Kimi", websiteURL: nil,
            sortIndex: 1, createdAt: 0, isCurrent: false, metaJSON: "{}",
            settingsConfigJSON: #"{"auth":{"OPENAI_API_KEY":"fake-kimi-key"},"config":"model = \"kimi-test\"\nbase_url = \"https://api.kimi.com/coding/v1/\""}"#)
        let local = CCSwitchQuotaTarget(id: "official-local:kimi:0", shortName: "Kimi", websiteURL: nil,
            kind: .kimi, isCurrent: false, apiKey: nil, baseURL: "https://api.kimi.com/coding/v1", accessToken: "old-cli-token")
        let discovered = CCSwitchQuotaCatalog.targets(from: [openCode, codex], currentProviderID: codex.id)
        #expect(discovered.first?.apiKey == "fake-kimi-key")
        #expect(discovered.first?.baseURL == "https://api.kimi.com/coding/v1")
        let targets = OfficialQuotaDiscovery.merge(ccSwitch: discovered, official: [local])
        #expect(targets.count == 1)
        #expect(targets.first?.id == codex.id)
        #expect(targets.first?.isCurrent == true)
        #expect(targets.first?.modelName == "kimi-test")
        #expect(targets.first?.shortName == "Kimi")
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: Array(discovered.reversed()), official: [local]) == targets)
        let transport = QuotaProviderTestTransport(bodies: [#"{"usage":{"used":10,"limit":100},"limits":[]}"#])
        let chips = try await AccountQuotaClient(transport: transport).refresh(targets: targets)
        #expect(chips.count == 1)
        guard case .windows = chips.first?.status else { Issue.record("Expected parsed Kimi quota"); return }
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fake-kimi-key")
    }

    @Test func kimiKeepsDifferentExplicitKeysAndOAuthWithoutAConfiguredKey() throws {
        let first = try #require(OfficialQuotaAccount(providerID: "kimi", label: "first", apiKey: "fake-one").target)
        let second = try #require(OfficialQuotaAccount(providerID: "kimi", label: "second", apiKey: "fake-two").target)
        let local = CCSwitchQuotaTarget(id: "official-local:kimi:0", shortName: "Kimi", websiteURL: nil,
            kind: .kimi, isCurrent: false, apiKey: nil, baseURL: "https://api.kimi.com/coding/v1", accessToken: "cli-token")
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: [], official: [first, second, local]).map(\.id) == [first.id, second.id])
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: [], official: [local]) == [local])
        let placeholder = CCSwitchQuotaTarget(id: "kimi-placeholder", shortName: "Kimi", websiteURL: nil,
            kind: .kimi, isCurrent: true, apiKey: "proxy-local", baseURL: "https://api.kimi.com/coding/v1")
        let hydrated = OfficialQuotaDiscovery.merge(ccSwitch: [placeholder], official: [local])
        #expect(hydrated.count == 1)
        #expect(hydrated.first?.id == placeholder.id)
        #expect(hydrated.first?.isCurrent == true)
        #expect(hydrated.first?.accessToken == local.accessToken)
        #expect(hydrated.first?.apiKey == nil)
        let keyHydrated = OfficialQuotaDiscovery.merge(ccSwitch: [placeholder], official: [first])
        #expect(keyHydrated.count == 1)
        #expect(keyHydrated.first?.id == placeholder.id)
        #expect(keyHydrated.first?.apiKey == "fake-one")
    }

    @Test func differentKimiKeysShowTheirCCSwitchSources() {
        let targets = [
            CCSwitchQuotaTarget(id: "cc-switch:opencode:kimi", shortName: "Kimi", websiteURL: nil,
                kind: .kimi, isCurrent: false, apiKey: "fake-one", baseURL: "https://api.kimi.com/coding/v1"),
            CCSwitchQuotaTarget(id: "kimi-codex", shortName: "Kimi 2", websiteURL: nil,
                kind: .kimi, isCurrent: true, apiKey: "fake-two", baseURL: "https://api.kimi.com/coding/v1"),
        ]
        let merged = OfficialQuotaDiscovery.merge(ccSwitch: targets, official: [])
        #expect(merged.map(\.shortName) == ["Kimi · OpenCode", "Kimi · Codex"])
        #expect(merged.map(\.id) == targets.map(\.id))
        #expect(OfficialQuotaDiscovery.merge(ccSwitch: merged, official: []) == merged)
    }

    @Test func quotaDiscoveryIncludesOtherCCSwitchAppsWithIndependentIDs() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appending(path: "cc-switch.db")
        var connection: OpaquePointer?
        #expect(sqlite3_open(PlatformPaths.fileSystemPath(database), &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        let sql = """
        CREATE TABLE providers(id TEXT, app_type TEXT, name TEXT, settings_config TEXT, website_url TEXT, created_at INTEGER, sort_index INTEGER, meta TEXT, is_current INTEGER);
        INSERT INTO providers VALUES('same','codex','Kimi','{}',NULL,0,0,'{}',1);
        INSERT INTO providers VALUES('same','claude','MiniMax','{}',NULL,0,1,'{}',1);
        """
        #expect(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
        guard case let .records(all) = CCSwitchProviderStore.loadQuotaProviders(databaseURL: database),
              case let .records(codex) = CCSwitchProviderStore.loadCodexProviders(databaseURL: database) else { Issue.record("Database query failed"); return }
        #expect(codex.count == 1)
        #expect(Set(all.map(\.id)) == ["same", "cc-switch:claude:same"])
        #expect(all.first(where: { $0.id == "same" })?.isCurrent == true)
        #expect(all.first(where: { $0.id == "cc-switch:claude:same" })?.isCurrent == false)
    }
}

private actor QuotaProviderTestTransport: AccountQuotaTransport {
    var requests: [URLRequest] = []
    private var bodies: [String]
    private let status: Int
    init(bodies: [String], status: Int = 200) { self.bodies = bodies; self.status = status }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        requests.append(request)
        guard !bodies.isEmpty else { throw URLError(.badServerResponse) }
        return AccountQuotaHTTPResponse(statusCode: status, headers: [:], body: Data(bodies.removeFirst().utf8))
    }
}

private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appending(path: "quota-providers-\(UUID().uuidString)") }
private func write(_ value: String, _ file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(value.utf8).write(to: file)
}
