import Foundation
import Testing
@testable import LeaderboardKit
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

struct KitCoverageBoundaryTests {
    @Test func presentationSupportsEverySourceLanguageAndMissingDate() throws {
        for language in AppLanguage.allCases {
            #expect(!language.locale.identifier.isEmpty)
            for category in LeaderboardCategory.allCases {
                #expect(!LeaderboardPresentation.title(category, language: language).isEmpty)
            }
            for kind in LeaderboardKind.allCases {
                #expect(!kind.sourceLinkTitle.isEmpty)
                #expect(kind.sourceURL.scheme == "https")
                #expect(!LeaderboardPresentation.title(kind, language: language).isEmpty)
                #expect(!LeaderboardPresentation.explanation(kind, language: language).isEmpty)
                let board = Leaderboard(kind: kind, title: "Fixture", sourceUpdatedAt: Date(timeIntervalSince1970: 1000), sourceNote: "Source note", entries: [])
                #expect(LeaderboardPresentation.sourceHelp(kind, language: language, board: board).contains("Source note") == !kind.isUsage)
            }
            for failure in [LeaderboardFailure.offline, .sourceUnavailable] {
                for cached in [true, false] { #expect(!failure.message(language: language, hasCachedBoard: cached).isEmpty) }
            }
            #expect(!ModelOpenness.help(language: language).isEmpty)
        }
        #expect(LeaderboardPresentation.rankLabel(3) == "🥉")
        #expect(ModelOpenness.fromSource(["openWeightsUrl": "http://weights.invalid/model"]) == .open)
        #expect(ModelOpenness.fromSource(["openWeightsUrl": "https:weights"]) == nil)
        #expect(ModelOpenness.fromSource(["openWeightsUrl": 1]) == nil)
        #expect(LeaderboardKind(rawValue: "invalid") == nil)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LeaderboardKind.self, from: Data("\"invalid\"".utf8)) }
    }

    @Test func cacheRejectsCorruptionPreservesLegacyDatesAndSurvivesAnUnwritableParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cache.json"), cache = LeaderboardCache(fileURL: file)
        func bytes(_ date: String) -> Data {
            Data("{\"boards\":{\"arenaText\":{\"kind\":\"arenaText\",\"title\":\"Fixture\",\"fetchedAt\":\"\(date)\",\"entries\":[]}}}".utf8)
        }
        try bytes("2026-10-13T00:00:00Z").write(to: file)
        #expect(cache.load()?.boards[.arenaText]?.title == "Fixture")
        try bytes("invalid").write(to: file)
        #expect(cache.load() == nil)
        let invalid = Leaderboard(kind: .arenaText, title: "NaN date", fetchedAt: Date(timeIntervalSinceReferenceDate: .nan), entries: [])
        let previous = try Data(contentsOf: file)
        cache.save(.init(boards: [.arenaText: invalid]))
        #expect(try Data(contentsOf: file) == previous)
        let blocked = LeaderboardCache(fileURL: file.appendingPathComponent("child"))
        blocked.save(.init())
        #expect(blocked.load() == nil)
        #expect(try Data(contentsOf: file) == previous)
        let old = Leaderboard(kind: .arenaText, title: "old", sourceUpdatedAt: Date(timeIntervalSince1970: 2), fetchedAt: Date(timeIntervalSince1970: 3), entries: [])
        let noSourceDate = Leaderboard(kind: .arenaText, title: "new", fetchedAt: Date(timeIntervalSince1970: 4), entries: [])
        #expect(!noSourceDate.canReplace(old))
        let encoder = JSONEncoder()
        let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: [])
        let data = try encoder.encode(["boards": ["retired-source": board, "arenaText": board]])
        #expect(try JSONDecoder().decode(LeaderboardSnapshot.self, from: data).boards == [.arenaText: board])
    }

    @Test func unknownBrandsAndPurchaseFallbacksRemainSafe() {
        #expect(OrganizationLogoCatalog.resolvedKey(organization: nil) == nil)
        #expect(OrganizationLogoCatalog.resolvedKey(organization: nil, modelName: "Harness - GPTunknown") == nil)
        #expect(OrganizationLogoCatalog.initial(organization: nil, modelName: "123") == "1")
        #expect(OrganizationLogoCatalog.initial(organization: nil, modelName: "---") == "?")
        #expect(OrganizationLogoCatalog.initial(organization: "unknown", modelName: "Devin") == "D")
        let unknown = LeaderboardEntry(rank: 1, name: "Unknown", score: 1, brand: .init(key: "", colorHex: "#123456"))
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: unknown) == "#123456")
        let invalid = LeaderboardEntry(rank: 1, name: "Unknown", score: 1, brand: .init(key: "", colorHex: "#XXXXXX"))
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: invalid) == OrganizationLogoCatalog.fallbackColorHex(for: "Unknown"))
        #expect(OrganizationLogoCatalog.isAchromaticHex("#GGGGGG") == false)
        #expect(OrganizationLogoCatalog.displayBrandColorHex("invalid", isDark: true) == "invalid")
        #expect(PurchaseLinkCatalog.links(forOrganization: nil).isEmpty)
        let link = PurchaseLink(label: "Fixture", url: URL(string: "https://example.invalid")!)
        #expect(link.id == "Fixture|https://example.invalid")
        #expect(PurchaseLinkCatalog.preferredLink(from: [link], language: .chinese) == link)
        let entries = [LeaderboardEntry(rank: 1, name: "Z", score: 10, organization: "Fixture"),
                       LeaderboardEntry(rank: 1, name: "A", score: 10, organization: "Fixture"),
                       LeaderboardEntry(rank: 2, name: "B", score: 10, organization: "Fixture")]
        #expect(CompanyLeaderboard.rank(entries).first?.entry.name == "Fixture")
        #expect(CompanyLeaderboard.rank(entries).first?.components.map(\.name) == ["A", "Z", "B"])
        #expect(CompanyLeaderboard.rank([.init(rank: 1, name: "Devin", score: 1)]).first?.entry.name == "Devin")
    }

    @Test func missingLocalizationAndLicenseResourcesKeepSafeFallbacks() throws {
        #expect(AppLanguage.traditional("Fixture", transform: { _ in nil }) == "Fixture")
        #expect(OrganizationCountry.canada.localizedName(language: .english, localize: { _ in nil }) == "CA")
        #expect(BrandFont.licenseText(at: nil) == "")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        let resources = root.appendingPathComponent("Contents/Resources/Fonts")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info: [String: Any] = ["CFBundleIdentifier": "test.brand.\(UUID().uuidString)", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        let file = resources.appendingPathComponent("fixture.txt")
        try Data("License fixture".utf8).write(to: file)
        let bundle = try #require(Bundle(url: root))
        #expect(BrandFont.resource("fixture", extension: "txt", main: bundle) == file)
        #expect(BrandFont.licenseText(at: file) == "License fixture")
        try Data([255, 254, 255]).write(to: file)
        #expect(BrandFont.licenseText(at: file) == "")
        #expect(BrandFont.resource("missing", extension: "txt", main: bundle) == nil)
    }

    #if canImport(AppKit)
    @Test @MainActor func titleAlignmentGuidesParticipateInNativeLayout() {
        for alignment in [VerticalAlignment.bottom, .firstTextBaseline] {
            let view = NSHostingView(rootView: HStack(alignment: alignment) { ChineseBrandTitle(); Text("Fixture") })
            view.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
            view.layoutSubtreeIfNeeded()
            #expect(view.fittingSize.width > 0)
        }
    }
    #endif
}

struct SharedEndpointBoundaryTests {
    @Test func validatesEveryEndpointComponentWithoutChangingTheEnvironment() {
        #expect(SharedLeaderboardConfiguration.endpoint(value: nil) == nil)
        #expect(SharedLeaderboardConfiguration.endpoint != nil)
        for value in ["https://fixture.invalid", "https://fixture.invalid:443/path"] {
            #expect(SharedLeaderboardConfiguration.endpoint(value: value)?.absoluteString == value)
        }
        for value in ["", "http://fixture.invalid", "https:", "https://user@fixture.invalid", "https://user:pass@fixture.invalid", "https://fixture.invalid?q=1", "https://fixture.invalid#part", "https://["] {
            #expect(SharedLeaderboardConfiguration.endpoint(value: value)?.host == "invalid-shared-service.invalid")
        }
    }
}

struct CatalogURLBoundaryTests {
    @Test func staticCatalogValidationAndMissingOrganizationRemainExplicit() throws {
        #expect(LeaderboardPresentation.rankLabel(4) == "4")
        #expect(OrganizationLogoCatalog.logoURL(forOrganization: nil) == nil)
        #expect(OrganizationLogoCatalog.logoURL(forOrganization: "fixture-unknown") == nil)
        #expect(CompanyLeaderboard.displayName(key: "fixture", best: nil) == "fixture")
        #expect(CompanyLeaderboard.displayName(key: "fixture", best: .init(rank: 1, name: "Model", score: 1, organization: "Other")) == "fixture")
        #expect(try PurchaseLinkCatalog.validatedURL("https://fixture.invalid").host == "fixture.invalid")
        for value in ["https://[", "https://fixture.invalid/a b", "https://fixture.invalid/\n"] {
            #expect(throws: PurchaseLinkCatalog.URLValidationError.self) { try PurchaseLinkCatalog.validatedURL(value) }
        }
        let now = Date(timeIntervalSince1970: 1000)
        let old = Leaderboard(kind: .arenaText, title: "old", sourceUpdatedAt: now, fetchedAt: now, entries: [])
        let outdated = Leaderboard(kind: .arenaText, title: "new", sourceUpdatedAt: now.addingTimeInterval(-1), fetchedAt: now.addingTimeInterval(1), entries: [])
        #expect(!outdated.canReplace(old))
    }
}

#if canImport(AppKit)
struct BrandMetricBoundaryTests {
    @Test func baselineCalculationHandlesMissingFontOutlines() {
        #expect(ChineseBrandLayout.baseline(height: 40, firstGlyph: nil) == 20)
        let path = CGPath(rect: CGRect(x: 0, y: 2, width: 5, height: 10), transform: nil)
        #expect(ChineseBrandLayout.baseline(height: 40, firstGlyph: path) == 27)
    }
}
#endif

struct LicenseMetadataBoundaryTests {
    @Test func sourceLicenseFallbackRemainsExplicitForKnownAndUnknownLicenses() {
        #expect(ModelOpenness.fromLicense(nil) == nil)
        #expect(ModelOpenness.fromLicense("Proprietary") == .closed)
        #expect(ModelOpenness.fromLicense("Apache 2.0") == .open)
        #expect(ModelOpenness.fromLicense("fixture") == nil)
        for license in ModelOpenness.openLicenses { #expect(ModelOpenness.fromSource(["license": license]) == .open) }
        #expect(ModelOpenness.fromSource(["license": "Proprietary"]) == .closed)
    }
}

struct ProtectedCacheBoundaryTests {
    @Test func protectedWriteSuccessAndFallbackUseTheSameSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cache.json"), cache = LeaderboardCache(fileURL: file)
        var options: [Data.WritingOptions] = []
        cache.save(.init()) { data, destination, value in
            options.append(value)
            #expect(destination == file)
            let decoded = try JSONDecoder().decode(LeaderboardSnapshot.self, from: data)
            #expect(decoded == .init())
        }
        #expect(options.count == 1)
        for filter in LeaderboardOpennessFilter.allCases {
            for language in AppLanguage.allCases { #expect(!filter.title(language: language).isEmpty) }
        }
    }
}
