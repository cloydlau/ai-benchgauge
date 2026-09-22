import Foundation
import LeaderboardCore
import XCTest

final class CCSwitchQuotaCatalogTests: XCTestCase {
    func testBuildsVisibleProvidersInCCSwitchOrderAndMarksTheSelectedOneCurrent() {
        let records = [
            record(
                id: "qwen",
                name: "千问",
                createdAt: 1,
                meta: #"{"usage_script":{"enabled":false,"templateType":"balance"}}"#,
                settings: settings(key: "should-not-be-used", toml: "https://api.deepseek.com")
            ),
            record(
                id: "codex-official",
                name: "OpenAI Official",
                website: "https://chatgpt.com/codex",
                sortIndex: 0,
                createdAt: 2,
                isCurrent: true,
                meta: #"{"usage_script":{"enabled":true,"templateType":"official_subscription"}}"#,
                settings: settings(key: "official-key-must-not-leave", toml: "https://api.openai.com/v1")
            ),
            record(
                id: "kimi",
                name: "Kimi For Coding",
                website: "https://www.kimi.com/code",
                createdAt: 3,
                meta: #"{"usage_script":{"enabled":true,"templateType":"token_plan","codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
            record(
                id: "deepseek",
                name: "DeepSeek",
                website: "https://platform.deepseek.com",
                createdAt: 4,
                meta: #"{"usage_script":{"enabled":true,"templateType":"balance"}}"#,
                settings: settings(key: "deepseek-key", configObject: ["base_url": "https://api.deepseek.com"])
            ),
            record(
                id: "xai",
                name: "xAI (Grok) OAuth",
                website: "https://x.ai/grok",
                createdAt: 5,
                meta: #"{"providerType":"xai_oauth"}"#
            ),
            record(
                id: "zhipu",
                name: "Zhipu GLM",
                website: "https://open.bigmodel.cn",
                createdAt: 6,
                meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"zhipu"}}"#,
                settings: settings(key: "zhipu-key", toml: "https://open.bigmodel.cn/api/paas/v4")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: "xai")

        XCTAssertEqual(targets.map(\.id), ["codex-official", "kimi", "deepseek", "xai", "zhipu"])
        XCTAssertEqual(targets.map(\.kind), [.officialNote, .kimi, .deepseek, .xaiOAuth, .zhipu])
        XCTAssertEqual(targets.map(\.shortName), ["OpenAI", "Kimi", "DeepSeek", "xAI", "智谱"])
        XCTAssertEqual(targets.map(\.isCurrent), [false, false, false, true, false])
        XCTAssertNil(targets[0].apiKey)
        XCTAssertEqual(targets[1].apiKey, "unit-test-key")
        XCTAssertEqual(targets[1].baseURL, "https://api.kimi.com/coding/v1")
        XCTAssertEqual(targets[2].baseURL, "https://api.deepseek.com")
        XCTAssertNil(targets[3].apiKey)
        XCTAssertEqual(targets[4].baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: targets[4].baseURL).absoluteString,
            "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        )
    }

    func testHiddenCurrentProviderFallsBackToTheDatabaseFlag() {
        let records = [
            record(id: "hidden", name: "千问", meta: #"{"usage_script":{"enabled":false}}"#),
            record(
                id: "kimi",
                name: "Kimi",
                isCurrent: true,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: "hidden")

        XCTAssertEqual(targets.map(\.id), ["kimi"])
        XCTAssertTrue(targets[0].isCurrent)
    }

    func testDropsProxyKeysLoopbackURLsAndDisambiguatesDuplicateNames() {
        let records = [
            record(
                id: "kimi-a",
                name: "Kimi A",
                createdAt: 1,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "proxy-local", toml: "http://127.0.0.1:9/v1")
            ),
            record(
                id: "kimi-b",
                name: "Kimi B",
                createdAt: 2,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: nil)

        XCTAssertEqual(targets.map(\.shortName), ["Kimi", "Kimi 2"])
        XCTAssertNil(targets[0].apiKey)
        XCTAssertNil(targets[0].baseURL)
        XCTAssertEqual(targets[1].apiKey, "unit-test-key")
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: nil).absoluteString,
            "https://api.z.ai/api/monitor/usage/quota/limit"
        )
    }
}

final class AccountQuotaFormattingTests: XCTestCase {
    func testFormatsQuotasTheWayCCSwitchShowsThem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let kimi = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(
                    name: "five_hour",
                    utilization: 0,
                    resetsAt: now.addingTimeInterval(4 * 3600 + 37 * 60)
                ),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: kimi, now: now), "5小时: 0% 4h37m")
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: kimi, now: now).map(\.tone),
            [.secondary, .green, .secondary]
        )

        let xai = chip(
            kind: .xaiOAuth,
            isCurrent: true,
            status: .windows([
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: 13,
                    resetsAt: now.addingTimeInterval((6 * 24 + 2) * 3600)
                ),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: xai, now: now), "7天: 13% 6d2h")
        XCTAssertTrue(AccountQuotaFormatting.help(for: xai, now: now).contains("当前供应商"))

        let zhipu = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval((2 * 24 + 3) * 3600)),
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
            ])
        )
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: zhipu, now: now),
            "5小时: 0%  7天: 100% 2d3h"
        )
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: zhipu, now: now).map(\.tone),
            [.secondary, .green, .secondary, .secondary, .red, .secondary]
        )

        let deepseek = chip(
            kind: .deepseek,
            status: .balances([
                ParsedBalance(currency: "USD", amount: 0),
                ParsedBalance(currency: "CNY", amount: 12.36),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: deepseek, now: now), "剩余 12.36 CNY")
    }

    func testCountdownBoundariesAndUtilizationTones() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(AccountQuotaFormatting.countdown(until: now, now: now))
        XCTAssertNil(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(-1), now: now))
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(45 * 60), now: now), "45m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(90 * 60), now: now), "1h30m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(24 * 3600), now: now), "24h0m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(25 * 3600), now: now), "1d1h")

        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 69.4), .green)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 69.5), .orange)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 89.4), .orange)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 89.5), .red)
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0),
        ])), now: now), AccountQuotaMessage.emptyBalance)
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: chip(kind: .kimi, status: .windows([])), now: now),
            AccountQuotaMessage.queryFailed
        )
    }
}

final class CCSwitchQuotaParserTests: XCTestCase {
    func testParsesKimiZhipuAndDeepSeekBodiesWithoutKeepingRawText() {
        let kimi = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":1760000000}}
        """#.utf8))
        guard case let .windows(kimiWindows) = kimi else {
            return XCTFail("expected kimi windows")
        }
        XCTAssertEqual(kimiWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(kimiWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [0, 75])
        XCTAssertNotNil(kimiWindows[0].resetsAt)
        XCTAssertNotNil(kimiWindows[1].resetsAt)

        let zhipu = CCSwitchQuotaParsers.parseZhipu(Data(#"""
        {"success":true,"data":{"limits":[{"type":"tokens_limit","unit":3,"percentage":0,"nextResetTime":1700000000000},{"type":"tokens_limit","unit":6,"percentage":100,"nextResetTime":1700200000000}]}}
        """#.utf8))
        guard case let .windows(zhipuWindows) = zhipu else {
            return XCTFail("expected zhipu windows")
        }
        XCTAssertEqual(zhipuWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(zhipuWindows.map(\.utilization), [0, 100])

        let deepseek = CCSwitchQuotaParsers.parseDeepSeek(Data(#"""
        {"balance_infos":[{"currency":"CNY","total_balance":"12.36"},{"currency":"USD","total_balance":0}]}
        """#.utf8))
        guard case let .balances(balances) = deepseek else {
            return XCTFail("expected balances")
        }
        XCTAssertEqual(balances, [
            ParsedBalance(currency: "CNY", amount: 12.36),
            ParsedBalance(currency: "USD", amount: 0),
        ])
    }

    func testRejectsMalformedBodies() {
        XCTAssertEqual(CCSwitchQuotaParsers.parseKimi(Data("not-json".utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseZhipu(Data(#"{"success":false}"#.utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseDeepSeek(Data("[]".utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseKimi(Data(#"{}"#.utf8)), .windows([]))
    }
}

final class AccountQuotaClientTests: XCTestCase {
    func testQueriesOnlyTheProviderHostAndKeepsTargetOrder() async throws {
        let transport = ScriptedQuotaTransport { request in
            let body: String
            switch request.url?.host {
            case "api.kimi.com":
                XCTAssertEqual(request.url?.path, "/coding/v1/usages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
                body = #"{"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":1760000000000}}]}"#
            case "api.deepseek.com":
                XCTAssertEqual(request.url?.path, "/user/balance")
                body = #"{"balance_infos":[{"currency":"CNY","total_balance":"12.36"}]}"#
            default:
                XCTFail("unexpected host \(request.url?.absoluteString ?? "")")
                body = "{}"
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/missing-xai-auth-\(UUID().uuidString).json")
        )
        let targets = [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: "must-not-be-sent"),
            quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key"),
            quotaTarget(id: "deepseek", name: "DeepSeek", kind: .deepseek, key: "unit-test-key", baseURL: "https://api.deepseek.com"),
        ]

        let chips = try await client.refresh(targets: targets)

        XCTAssertEqual(chips.map(\.id), ["official", "kimi", "deepseek"])
        XCTAssertEqual(chips.map(\.status), [
            .note(text: AccountQuotaMessage.officialSummary, help: AccountQuotaMessage.officialHelp),
            .windows([
                ParsedQuotaWindow(
                    name: "five_hour",
                    utilization: 0,
                    resetsAt: Date(timeIntervalSince1970: 1_760_000_000)
                ),
            ]),
            .balances([ParsedBalance(currency: "CNY", amount: 12.36)]),
        ])
        let hosts = transport.requests.compactMap { $0.url?.host }
        XCTAssertEqual(hosts.sorted(), ["api.deepseek.com", "api.kimi.com"])
        XCTAssertFalse(chips.contains { AccountQuotaFormatting.plainSummary(for: $0, now: Date()).contains("unit-test-key") })
    }

    func testBadKeyDoesNotKeepAStaleQuotaButNetworkLossDoes() async throws {
        let previous = AccountQuotaChip(
            id: "kimi",
            shortName: "Kimi",
            websiteURL: URL(string: "https://www.kimi.com/code"),
            kind: .kimi,
            isCurrent: false,
            status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil)])
        )
        let unauthorized = ScriptedQuotaTransport { _ in
            AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data("{}".utf8))
        }
        let unauthorizedClient = AccountQuotaClient(transport: unauthorized)
        let failed = try await unauthorizedClient.refresh(
            targets: [quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key", current: true)],
            previous: [previous]
        )
        XCTAssertEqual(failed.map(\.status), [.message(AccountQuotaMessage.queryFailed)])
        XCTAssertEqual(failed.map(\.isCurrent), [true])

        let offline = ScriptedQuotaTransport { _ in
            throw URLError(.timedOut)
        }
        let offlineClient = AccountQuotaClient(transport: offline)
        let kept = try await offlineClient.refresh(
            targets: [quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key", current: true)],
            previous: [previous]
        )
        XCTAssertEqual(kept.map(\.status), [previous.status])
        XCTAssertEqual(kept.first?.isCurrent, true)
    }

    func testMissingXAILoginDoesNotCallTheNetwork() async throws {
        let transport = ScriptedQuotaTransport { request in
            XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/missing-xai-auth-\(UUID().uuidString).json")
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil),
        ])
        XCTAssertEqual(chips.map(\.status), [.message(AccountQuotaMessage.reauthRequired)])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testZhipuUsesTheHostThatMatchesItsBaseURL() async throws {
        let transport = ScriptedQuotaTransport { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "unit-test-key")
            return AccountQuotaHTTPResponse(
                statusCode: 200,
                headers: [:],
                body: Data(#"{"success":true,"data":{"limits":[]}}"#.utf8)
            )
        }
        let client = AccountQuotaClient(transport: transport)
        _ = try await client.refresh(targets: [
            quotaTarget(
                id: "zhipu",
                name: "智谱",
                kind: .zhipu,
                key: "unit-test-key",
                baseURL: "https://open.bigmodel.cn/api/paas/v4"
            ),
        ])
    }
}

final class CCSwitchProviderStoreTests: XCTestCase {
    func testMissingDatabaseIsEmptyAndAnUnreadablePathIsUnavailable() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "missing-cc-switch-\(UUID().uuidString).db")
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: missing), .records([]))

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "not-a-db-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: directory), .unavailable)
    }

    func testLoadsOnlyCodexRowsAndTheSelectedProviderID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "cc-switch.db")
        let settingsURL = directory.appending(path: "settings.json")
        try Data(#"{"currentProviderCodex":" xai ","currentProviderClaude":"ignored"}"#.utf8)
            .write(to: settingsURL)
        XCTAssertEqual(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL), "xai")
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: directory.appending(path: "missing.json")))

        let kimiSettings = settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
        let sql = """
        CREATE TABLE providers (
            id TEXT NOT NULL,
            app_type TEXT NOT NULL,
            name TEXT NOT NULL,
            settings_config TEXT NOT NULL,
            website_url TEXT,
            created_at INTEGER,
            sort_index INTEGER,
            meta TEXT NOT NULL DEFAULT '{}',
            is_current INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('claude-1', 'claude', 'Claude', '{}', NULL, 1, NULL, '{}', 1);
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('kimi', 'codex', 'Kimi For Coding', \(sqlLiteral(kimiSettings)), 'https://www.kimi.com/code', 2, NULL, '{"usage_script":{"codingPlanProvider":"kimi"}}', 0);
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('xai', 'codex', 'xAI', '{}', NULL, 3, NULL, '{"providerType":"xai_oauth"}', 0);
        """
        try runSQLite(sql, database: databaseURL)

        let loaded = CCSwitchProviderStore.loadCodexProviders(databaseURL: databaseURL)
        guard case let .records(records) = loaded else {
            return XCTFail("expected records, got \(loaded)")
        }
        let targets = CCSwitchQuotaCatalog.targets(
            from: records,
            currentProviderID: CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)
        )
        XCTAssertEqual(targets.map(\.id), ["kimi", "xai"])
        XCTAssertEqual(targets.map(\.isCurrent), [false, true])
        XCTAssertEqual(targets[0].apiKey, "unit-test-key")
        XCTAssertNil(targets[1].apiKey)
        XCTAssertNil(targets[1].websiteURL)
    }
}

final class XaiEndpointValidatorTests: XCTestCase {
    func testAcceptsOnlyTheXAIAuthHost() {
        XCTAssertEqual(
            XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai/oauth2/token")?.absoluteString,
            "https://auth.x.ai/oauth2/token"
        )
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("http://auth.x.ai/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://evil.example/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai.evil/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://user:pass@auth.x.ai/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai:8443/oauth2/token"))
        XCTAssertTrue(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai/"))
        XCTAssertFalse(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai.evil"))
    }

    func testClassifiesGrokFailuresWithoutReadingABody() {
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 401, grpcStatus: nil), .reauth)
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 429, grpcStatus: nil), .transient)
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 16), .reauth)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            GrokBillingParser.tierName(resetsAt: now.addingTimeInterval(7 * 86_400), now: now),
            "weekly_limit"
        )
    }
}

private final class ScriptedQuotaTransport: AccountQuotaTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> AccountQuotaHTTPResponse

    init(handler: @escaping @Sendable (URLRequest) throws -> AccountQuotaHTTPResponse) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        record(request)
        return try handler(request)
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        seen.append(request)
        lock.unlock()
    }
}

private func record(
    id: String,
    name: String,
    website: String? = nil,
    sortIndex: Int? = nil,
    createdAt: Int64 = 0,
    isCurrent: Bool = false,
    meta: String = "{}",
    settings: String = "{}"
) -> CCSwitchProviderRecord {
    CCSwitchProviderRecord(
        id: id,
        name: name,
        websiteURL: website,
        sortIndex: sortIndex,
        createdAt: createdAt,
        isCurrent: isCurrent,
        metaJSON: meta,
        settingsConfigJSON: settings
    )
}

private func settings(key: String?, toml: String) -> String {
    settings(key: key, config: "base_url = \"\(toml)\"")
}

private func settings(key: String?, config: Any) -> String {
    var object: [String: Any] = ["config": config]
    if let key {
        object["auth"] = ["OPENAI_API_KEY": key]
    }
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private func settings(key: String?, configObject: [String: Any]) -> String {
    settings(key: key, config: configObject)
}

private func chip(
    kind: CCSwitchQuotaKind,
    isCurrent: Bool = false,
    status: AccountQuotaChip.Status
) -> AccountQuotaChip {
    AccountQuotaChip(
        id: kind.shortTestID,
        shortName: "Name",
        websiteURL: URL(string: "https://example.com"),
        kind: kind,
        isCurrent: isCurrent,
        status: status
    )
}

private func quotaTarget(
    id: String,
    name: String,
    kind: CCSwitchQuotaKind,
    key: String?,
    baseURL: String? = nil,
    current: Bool = false
) -> CCSwitchQuotaTarget {
    CCSwitchQuotaTarget(
        id: id,
        shortName: name,
        websiteURL: URL(string: "https://example.com/\(id)"),
        kind: kind,
        isCurrent: current,
        apiKey: key,
        baseURL: baseURL
    )
}

private extension CCSwitchQuotaKind {
    var shortTestID: String {
        switch self {
        case .officialNote: "official"
        case .kimi: "kimi"
        case .zhipu: "zhipu"
        case .deepseek: "deepseek"
        case .xaiOAuth: "xai"
        }
    }
}

private func sqlLiteral(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

private func runSQLite(_ sql: String, database: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path(percentEncoded: false)]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTFail("sqlite3 exited \(process.terminationStatus): \(text)")
    }
}
