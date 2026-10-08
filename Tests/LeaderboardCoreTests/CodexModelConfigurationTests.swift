import Foundation
import LeaderboardCore
import Testing

struct CodexModelConfigurationTests {
    private func target(kind: CCSwitchQuotaKind = .officialNote, current: Bool = true,
                        baseURL: String? = nil) -> CCSwitchQuotaTarget {
        CCSwitchQuotaTarget(id: "fixture", shortName: "OpenAI", modelName: "gpt-6-astra",
                            websiteURL: nil, kind: kind, isCurrent: current,
                            apiKey: nil, baseURL: baseURL)
    }

    @Test func liveSolOverridesSavedAstraInMenuOnly() throws {
        let config = try #require(CodexModelConfiguration.parse("model = \"gpt-6.1-sol\"\n"))
        let current = target()
        let chip = AccountQuotaChip(id: current.id, shortName: current.shortName,
            modelName: current.modelName, websiteURL: nil, kind: .officialNote, isCurrent: true,
            status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 25, resetsAt: nil)]))
        let text = AccountQuotaFormatting.menuBarText(forChips: [chip],
            currentModelName: config.modelName(matching: current))
        #expect(text == AccountQuotaMenuBarText(name: "gpt-6.1-sol", fullName: "gpt-6.1-sol", quota: "5h 75%"))
        #expect(AccountQuotaFormatting.menuBarText(forChips: [chip])?.name == "gpt-6-astra")
        #expect(AccountQuotaFormatting.menuBarText(forChips: [chip], currentModelName: "  ")?.name == "gpt-6-astra")
    }

    @Test func ignoresProfilesAndProviderTableModels() {
        let config = CodexModelConfiguration.parse("""
        # model = "ignored"
        model = 'gpt-6.1-sol' # the live default
        [profiles.other]
        model = "gpt-6-astra"
        [model_providers.custom]
        model = "another-model"
        base_url = "https://other.example/v1"
        """)
        #expect(config?.model == "gpt-6.1-sol")
        #expect(config?.provider == nil)
        #expect(CodexModelConfiguration.parse("[profiles.other]\nmodel = \"gpt-6-astra\"") == nil)
        #expect(CodexModelConfiguration.parse("model = \"\"") == nil)
        #expect(CodexModelConfiguration.parse("model = unquoted") == nil)
        #expect(CodexModelConfiguration.parse("model = \"truncated") == nil)
    }

    @Test func matchesOnlyCurrentAndCompatibleProvider() throws {
        let official = CodexModelConfiguration(model: "gpt-6.1-sol")
        #expect(official.modelName(matching: target()) == "gpt-6.1-sol")
        #expect(official.modelName(matching: target(current: false)) == nil)
        #expect(official.modelName(matching: target(kind: .kimi)) == nil)
        let custom = try #require(CodexModelConfiguration.parse("""
        model = "k3"
        model_provider = "custom"
        [model_providers."custom"]
        base_url = "https://api.kimi.com/coding/v1/"
        """))
        #expect(custom.modelName(matching: target(kind: .kimi, baseURL: "https://api.kimi.com/coding/v1")) == "k3")
        #expect(custom.modelName(matching: target()) == nil)
        #expect(custom.modelName(matching: target(kind: .deepseek, baseURL: "https://api.deepseek.com/v1")) == nil)
        #expect(custom.modelName(matching: target(kind: .kimi)) == nil)
    }

    @Test func missingLiveConfigIsOptionalAndChangesAreReread() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "model-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appending(path: ".codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: [:]) == nil)
        let file = root.appending(path: "config.toml")
        try Data("model = \"gpt-6-astra\"".utf8).write(to: file)
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: [:])?.model == "gpt-6-astra")
        try Data("model = \"gpt-6.1-sol\"".utf8).write(to: file)
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: [:])?.model == "gpt-6.1-sol")
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: ["CODEX_HOME": root.path])?.model == "gpt-6.1-sol")
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: ["CODEX_HOME": home.appending(path: "absent").path]) == nil)
        try Data("model = broken".utf8).write(to: file)
        #expect(CCSwitchProviderStore.currentCodexModelConfiguration(homeDirectory: home, environment: [:]) == nil)
    }
    private func proxyTargets() -> [CCSwitchQuotaTarget] {
        [CCSwitchQuotaTarget(id: "openai", shortName: "OpenAI", modelName: "gpt-5.6-sol",
            websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil,
            accessToken: "unit-test-access", accountID: "unit-test-account"),
         CCSwitchQuotaTarget(id: "kimi", shortName: "Kimi", modelName: "kimi-k3",
            websiteURL: URL(string: "https://kimi.com"), kind: .kimi, isCurrent: false,
            apiKey: "unit-test-kimi-key", baseURL: "https://api.kimi.com/coding/v1")]
    }

    private func proxyChips(kimiStatus: AccountQuotaChip.Status) -> [AccountQuotaChip] {
        proxyTargets().map { target in
            AccountQuotaChip(id: target.id, shortName: target.shortName, modelName: target.modelName,
                websiteURL: target.websiteURL, kind: target.kind, isCurrent: target.isCurrent,
                status: target.kind == .kimi ? kimiStatus : .windows([
                    ParsedQuotaWindow(name: "five_hour", utilization: 96, resetsAt: nil)
                ]))
        }
    }

    @Test func loopbackProxySelectsUniqueKimiWithItsOwnQuotaAndCredentials() throws {
        let original = proxyTargets()
        for url in ["http://127.0.0.1:15721/v1", "http://localhost:15721/v1", "http://[::1]:15721/v1"] {
            let config = CodexModelConfiguration(model: "kimi-k3", provider: "custom", baseURL: url)
            let selected = config.selectingCurrentTarget(in: original)
            #expect(selected.filter(\.isCurrent).map(\.id) == ["kimi"])
            #expect(selected[1].apiKey == original[1].apiKey)
            #expect(selected[1].baseURL == original[1].baseURL)
            #expect(selected[1].websiteURL == original[1].websiteURL)
            #expect(selected[0].accessToken == original[0].accessToken)
            #expect(selected[0].accountID == original[0].accountID)
            #expect(config.modelName(matching: selected[1]) == "kimi-k3")
            #expect(config.modelName(matching: selected[0]) == nil)
            let menu = try #require(config.menuBarText(for: proxyChips(kimiStatus: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 23, resetsAt: nil)
            ])), targets: original))
            #expect(menu.fullName == "kimi-k3")
            #expect(menu.quota == "5h 77%")
        }
        #expect(original.first?.isCurrent == true)
    }

    @Test func proxyModelKeepsKimiPendingAndLoginFailureInsteadOfOpenAIQuota() throws {
        let config = CodexModelConfiguration(model: "kimi-k3", provider: "custom", baseURL: "http://localhost:15721/v1")
        for (status, expected) in [(AccountQuotaChip.Status.pending, AccountQuotaMessage.querying),
                                  (.message(AccountQuotaMessage.reauthRequired), AccountQuotaMessage.reauthRequired)] {
            let menu = try #require(config.menuBarText(for: proxyChips(kimiStatus: status), targets: proxyTargets()))
            #expect(menu.name == "kimi-k3")
            #expect(menu.quota == expected)
        }
    }

    @Test func ambiguousAndUnknownProxyRoutesNeverBorrowAnotherAccountQuota() throws {
        let existing = proxyTargets()
        let duplicate = CCSwitchQuotaTarget(id: "kimi-2", shortName: "Kimi second", modelName: "kimi-k3",
            websiteURL: nil, kind: .kimi, isCurrent: false, apiKey: "unit-test-other-key", baseURL: "https://api.kimi.com/coding/v1")
        let config = CodexModelConfiguration(model: "kimi-k3", provider: "custom", baseURL: "http://localhost:15721/v1")
        #expect(config.selectingCurrentTarget(in: existing + [duplicate]).allSatisfy { !$0.isCurrent })
        let ambiguous = try #require(config.menuBarText(for: proxyChips(kimiStatus: .pending), targets: existing + [duplicate]))
        #expect(ambiguous.fullName == "kimi-k3")
        #expect(ambiguous.quota == AccountQuotaMessage.queryFailed)
        let unknown = CodexModelConfiguration(model: "unknown-proxy-model", provider: "custom", baseURL: "http://localhost:15721/v1")
        #expect(unknown.selectingCurrentTarget(in: existing).allSatisfy { !$0.isCurrent })
        #expect(unknown.menuBarText(for: proxyChips(kimiStatus: .pending), targets: existing)?.fullName == "unknown-proxy-model")
        #expect(unknown.menuBarText(for: [], targets: [])?.quota == AccountQuotaMessage.queryFailed)
    }

    @Test func directRoutesRemainStrictAndOfficialSelectionIsRetained() {
        let targets = proxyTargets()
        let direct = CodexModelConfiguration(model: "kimi-k3", provider: "custom", baseURL: "https://api.kimi.com/coding/v1/")
        #expect(direct.selectingCurrentTarget(in: targets).filter(\.isCurrent).map(\.id) == ["kimi"])
        let remote = CodexModelConfiguration(model: "kimi-k3", provider: "custom", baseURL: "https://other.example/v1")
        #expect(remote.selectingCurrentTarget(in: targets).allSatisfy { !$0.isCurrent })
        let official = CodexModelConfiguration(model: "gpt-6.1-sol")
        #expect(official.selectingCurrentTarget(in: targets).filter(\.isCurrent).map(\.id) == ["openai"])
    }

}
