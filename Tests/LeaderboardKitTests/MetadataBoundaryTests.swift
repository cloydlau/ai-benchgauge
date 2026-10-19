import Foundation
import Testing
@testable import LeaderboardKit

private final class UnavailableNumberFormatter: NumberFormatter, @unchecked Sendable {
    override func string(from number: NSNumber) -> String? { nil }
}

struct MetadataBoundaryTests {
    @Test func distributionResourcesPreservePriorityAndReportInvalidNotices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ name: String) throws -> Bundle {
            let path = root.appendingPathComponent(name + ".bundle")
            try FileManager.default.createDirectory(at: path.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test." + name, "CFBundlePackageType": "BNDL"], format: .xml, options: 0)
                .write(to: path.appendingPathComponent("Contents/Info.plist"))
            return try #require(Bundle(url: path))
        }
        let main = try bundle("main"), module = try bundle("module"), empty = try bundle("empty")
        let mainFile = main.resourceURL!.appendingPathComponent("notice.txt")
        let moduleFile = module.resourceURL!.appendingPathComponent("notice.txt")
        let executable = root.appendingPathComponent("notice.txt")
        try Data("Module".utf8).write(to: moduleFile)
        try Data("Main".utf8).write(to: mainFile)
        #expect(try BundledResource.url("notice", extension: "txt", main: empty, module: module).resolvingSymlinksInPath().path == moduleFile.resolvingSymlinksInPath().path)
        #expect(try BundledResource.url("notice", extension: "txt", main: empty, module: module, executable: executable).resolvingSymlinksInPath().path == moduleFile.resolvingSymlinksInPath().path)
        try Data("Executable".utf8).write(to: executable)
        #expect(try BundledResource.url("notice", extension: "txt", main: empty, module: module, executable: executable) == executable)
        #expect(try BundledResource.url("notice", extension: "txt", main: main, module: module, executable: executable).resolvingSymlinksInPath().path == mainFile.resolvingSymlinksInPath().path)
        #expect(throws: CocoaError.self) { try BundledResource.url("absent", extension: "txt", main: main, module: module) }
        #expect(try ModelsDevAttribution.readLicense(at: mainFile) == "Main")
        #expect(throws: (any Error).self) { try EpochAttribution.load(from: executable) }
        #expect(throws: (any Error).self) { try EpochAttribution.load(from: root.appendingPathComponent("missing")) }
        try Data([255]).write(to: mainFile)
        #expect(throws: (any Error).self) { try ModelsDevAttribution.readLicense(at: mainFile) }
        #expect(throws: (any Error).self) { try ModelsDevAttribution.readLicense(at: root.appendingPathComponent("missing")) }
        #expect(EpochAttribution.localizedChanges(["en": "English fallback"], language: .chinese) == "English fallback")
        #expect(ModelsDevAttribution.credit(language: .english) == "Model information: models.dev")
        #expect(ModelDetails.loadLabels(at: nil).isEmpty)
        #expect(ModelDetails.loadLabels(at: root.appendingPathComponent("missing")).isEmpty)
        #expect(ModelDetails.loadLabels(at: mainFile).isEmpty)
        try Data("not JSON".utf8).write(to: mainFile)
        #expect(ModelDetails.loadLabels(at: mainFile).isEmpty)
        try Data("{\"key\":[\"English\"]}".utf8).write(to: mainFile)
        let labels = ModelDetails.loadLabels(at: mainFile)
        #expect(ModelDetails.localizedText("key", language: .english, labels: labels) == "English")
        #expect(ModelDetails.localizedText("key", language: .traditionalChinese, labels: labels) == "key")
        #expect(ModelDetails.text("future_field", language: .english) == "future field")
    }

    @Test func futureModelFieldsKeepNullAndNestedValuesAndSafeLinks() throws {
        let json = Data("{\"null\":null,\"array\":[true,1,\"value\",{}]}".utf8)
        let value = try JSONDecoder().decode(ModelDetailValue.self, from: json)
        #expect(try JSONDecoder().decode(ModelDetailValue.self, from: JSONEncoder().encode(value)) == value)
        #expect(ModelDetails.map([1, 2]).isEmpty)
        #expect(ModelDetails.map(["number": Double.nan]).isEmpty)
        let attrs: [String: Any] = ["description": "", "family": "text", "type": "true", "knowledge": NSNull(),
            "modalities": [], "links": ["credential": "https://user:pass@example.com", "broken": "https://[", "emptyHost": "https:", "password": "https://:pass@example.com"],
            "weights": ["value", ["nested": 2], NSNull()],
            "benchmarks": [false, ["name": NSNull(), "score": 2], ["score": 3]],
            "null": NSNull(), "number": 1.5]
        let obj: [String: Any] = ["id": "unknown", "name": "Unknown", "source": "models.dev", "sourceURL": "https://models.dev", "revision": "revision", "fetchedAt": "2026-10-20", "limit": [:], "openWeights": false, "attributes": attrs,
            "offers": [["provider": "p", "providerName": "Provider", "modelID": "id", "name": "Unknown", "currency": "USD", "unit": "per-million-tokens", "limit": [:], "status": "active", "cost": ["input": 0, "output": 2]]]]
        let data = try JSONSerialization.data(withJSONObject: obj)
        let metadata = try JSONDecoder().decode(ModelMetadata.self, from: data)
        let entry = LeaderboardEntry(rank: 1, name: "Unknown", score: 1, modelMetadata: metadata)
        #expect(entry.resolvedOpenness == .closed)
        let sections = ModelDetails.sections(for: entry, language: .english, formatter: UnavailableNumberFormatter())
        #expect(sections.first(where: { $0.id == "general" })?.rows.contains(where: { $0.value == "Unknown" }) == true)
        #expect(sections.first(where: { $0.id == "benchmark-1" })?.title.hasSuffix("2") == true)
        #expect(sections.first(where: { $0.id == "benchmark-2" })?.title.hasSuffix("3") == true)
        #expect(sections.first(where: { $0.id == "links" })?.rows.allSatisfy({ $0.url == nil }) == true)
        #expect(sections.flatMap(\.rows).contains(where: { $0.value == "1.5" }))
        #expect(sections.first(where: { $0.id == "provider-0" })?.summary?.contains("$ ·") == true)
        var minimal = obj; minimal.removeValue(forKey: "attributes")
        let minimalModel = try JSONDecoder().decode(ModelMetadata.self, from: JSONSerialization.data(withJSONObject: minimal))
        let minimalSections = ModelDetails.sections(for: .init(rank: 1, name: "Unknown", score: 1, modelMetadata: minimalModel), language: .english)
        #expect(minimalSections.contains(where: { $0.id == "general" }))
        #expect(!minimalSections.contains(where: { $0.id == "additional" }))
        var foreign = obj; foreign["source"] = "unverified"
        let other = try JSONDecoder().decode(ModelMetadata.self, from: JSONSerialization.data(withJSONObject: foreign))
        #expect(ModelDetails.sections(for: .init(rank: 1, name: "Unknown", score: 1, modelMetadata: other), language: .english).isEmpty)
        #expect(LeaderboardEntry(rank: 1, name: "Unknown", score: 1, modelMetadata: other).resolvedOpenness == nil)
        let old = Leaderboard(kind: .arenaText, title: "Previous", sourceUpdatedAt: Date(), entries: [])
        let new = Leaderboard(kind: .arenaText, title: "New", sourceUpdatedAt: old.sourceUpdatedAt, entries: [])
        #expect(new.canReplace(old))
    }

    @Test func officialArenaPublicationDatesUseDateOnlyForAllLanguages() {
        for language in AppLanguage.allCases {
            let board = Leaderboard(kind: .arenaText, title: "Dataset", sourceUpdatedAt: Date(timeIntervalSince1970: 123456),
                sourceNote: ArenaAttribution.sourceURL, entries: [])
            #expect(!LeaderboardPresentation.sourceHelp(.arenaText, language: language, board: board).isEmpty)
            #expect(!LeaderboardPresentation.sourceTimeHelp(board, language: language).isEmpty)
            let fetched = board.fetchedAt.addingTimeInterval(60)
            let legacy = Leaderboard(kind: .arenaText, title: "Legacy", sourceUpdatedAt: fetched,
                fetchedAt: fetched, entries: [])
            #expect(!legacy.canReplace(board))
            let replacement = Leaderboard(kind: .arenaText, title: "Next dataset", sourceUpdatedAt: fetched,
                sourceNote: ArenaAttribution.sourceURL, fetchedAt: fetched, entries: [])
            #expect(replacement.canReplace(board))
        }
    }

    @Test func legacyParsersRejectEmptySourceRatherThanCreateAnEmptyBoard() {
        let fetcher = LeaderboardFetcher()
        for kind in LeaderboardKind.allCases {
            #expect(throws: (any Error).self) { try fetcher.parse(kind, html: "") }
        }
    }
}
