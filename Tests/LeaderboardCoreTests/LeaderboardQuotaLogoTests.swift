import Foundation
import LeaderboardCore
import Testing

struct LeaderboardQuotaLogoTests {
    private func png() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Tests/fixtures/shared-brand-64.png"))
    }

    @Test func providerIdentityDoesNotDependOnAccountLabelsOrLanguage() {
        let providers: [(CCSwitchQuotaKind, String, String)] = [
            (.officialNote, "openai", "O"), (.kimi, "kimi", "K"), (.deepseek, "deepseek", "D"),
            (.qwen, "qwen", "Q"), (.xaiOAuth, "spacexai", "X"), (.zhipu, "zai", "Z"),
            (.minimax, "minimax", "M"), (.stepfun, "stepfun", "S"),
            (.blackForestLabs, "blackforestlabs", "B"), (.luma, "luma", "L"),
            (.claude, "anthropic", "A"), (.gemini, "google", "G")
        ]
        for (kind, key, initial) in providers {
            #expect(LeaderboardQuotaProviders.organizationKey(for: kind) == key)
            #expect(LeaderboardQuotaProviders.logoInitial(for: kind) == initial)
        }
    }

    @Test func qwenQuotaUsesProductMarkInsteadOfCachedAlibabaCompanyMark() throws {
        let alibaba = try png()
        let logos = ["qwen": alibaba, "openai": alibaba]
        let qwen = LeaderboardQuotaProviders.logoPNGData(for: .qwen, providerLogos: logos)
        #expect(qwen == OrganizationLogoCatalog.qwenProductPNGData)
        #expect(qwen != alibaba)
        #expect(LeaderboardQuotaProviders.logoPNGData(for: .qwen, providerLogos: [:]) == qwen)
        #expect(LeaderboardQuotaProviders.logoPNGData(for: .officialNote, providerLogos: logos) == alibaba)
        #expect(LeaderboardQuotaProviders.logoPNGData(for: .officialNote, providerLogos: [:]) == nil)
    }

    @Test func sharedManufacturerImageSurvivesOfflineCacheWithoutUsingModelMark() throws {
        let image = try png()
        let modelImage = image + Data([0])
        let entry = LeaderboardEntry(rank: 1, name: "Wan 3", score: 99, organization: "Alibaba",
            brand: OrganizationBrand(key: "model-wan", colorHex: "#123456", pngData: modelImage),
            organizationBrand: OrganizationBrand(key: "Alibaba", colorHex: "#623AE7", pngData: image))
        let snapshot = LeaderboardSnapshot(boards: [.artificialAnalysisTextToVideo:
            Leaderboard(kind: .artificialAnalysisTextToVideo, title: "Synthetic", entries: [entry])])
        let cached = try JSONDecoder().decode(LeaderboardSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(OrganizationLogoCatalog.organizationLogoPNGData(in: cached) == ["qwen": image])
        #expect(OrganizationLogoCatalog.rowLogoPNGData(for: entry) == modelImage)
        #expect(OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: true) == image)
    }

    @Test func newestValidManufacturerWinsAndMissingOrWrongImagesCannotHideCachedMark() throws {
        let older = try png(), newer = older + Data([0])
        func row(_ key: String, _ data: Data?) -> LeaderboardEntry {
            LeaderboardEntry(rank: 1, name: "GPT fixture", score: 99, organization: "OpenAI",
                brand: OrganizationBrand(key: key, colorHex: "#10A37F", pngData: data))
        }
        let oldBoard = Leaderboard(kind: .arenaText, title: "Cached", fetchedAt: Date(timeIntervalSince1970: 1), entries: [row("openai", older)])
        for candidate in [row("openai", nil), row("openai", Data("bad".utf8)), row("model-gpt", newer), row("anthropic", newer)] {
            let current = Leaderboard(kind: .artificialAnalysis, title: "New", fetchedAt: Date(timeIntervalSince1970: 2), entries: [candidate])
            #expect(OrganizationLogoCatalog.organizationLogoPNGData(in: .init(boards: [.arenaText: oldBoard, .artificialAnalysis: current])) == ["openai": older])
            #expect(OrganizationLogoCatalog.organizationLogoPNGData(in: .init(boards: [.artificialAnalysis: current])).isEmpty)
        }
        let current = Leaderboard(kind: .artificialAnalysis, title: "New", fetchedAt: Date(timeIntervalSince1970: 2), entries: [row("Open AI", newer)])
        #expect(OrganizationLogoCatalog.organizationLogoPNGData(in: .init(boards: [.arenaText: oldBoard, .artificialAnalysis: current])) == ["openai": newer])
        #expect(OrganizationLogoCatalog.organizationLogoPNGData(in: .init()).isEmpty)
    }
}
