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
}
