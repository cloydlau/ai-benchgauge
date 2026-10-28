import Foundation
import Testing
@testable import LeaderboardKit

private func eciCSV(_ first: [String: String] = [:], count: Int = 22) -> String {
    let header = ["Model", "Display name", "eci", "Organization", "Country (of organization)", "Accessibility group", "date", "model_versions"]
    let rows = (0..<count).map { index in
        var value = ["Model": "model-\(index)", "Display name": "Model \(index)", "eci": "\(170 - Double(index) / 3)",
                     "Organization": "Maker", "Country (of organization)": "United States of America", "Accessibility group": "Closed weights",
                     "date": "2099-01-01", "model_versions": "[\"a\",\"b\"]"]
        if index == 0 { value.merge(first) { _, new in new } }
        return header.map { key in "\"" + value[key]!.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
    }
    return header.joined(separator: ",") + "\r\n" + rows.joined(separator: "\r\n") + "\r\n"
}

@Test func epochOfficialCSVPreservesScoresAndMetadata() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let board = try EpochECIParser.parse("\u{FEFF}" + eciCSV(["Display name": "模型, \"Alpha\"", "eci": "166.82", "Accessibility group": "Open weights", "Country (of organization)": "Hong Kong", "model_versions": "a\nb"]), fetchedAt: date)
    #expect(board.kind == .epochECI)
    #expect(board.sourceUpdatedAt == nil)
    #expect(board.fetchedAt == date)
    #expect(board.entries.count == 22)
    let entry = try #require(board.entries.first { $0.modelID == "model-0" })
    #expect(entry.name == "模型, \"Alpha\"")
    #expect(entry.score == 166.82)
    #expect(entry.openness == .open)
    #expect(entry.developerCountry?.countryCode == "CN")
    #expect(board.entries.map(\.rank) == Array(1...22))
    #expect(LeaderboardKind.epochECI.sourceURL.absoluteString == "https://epoch.ai/eci")
    #expect(LeaderboardKind.epochECI.dataURL.absoluteString == "https://epoch.ai/data/eci_scores.csv")
    let unknown = try EpochECIParser.parse(eciCSV(["Display name": "", "Accessibility group": "Other", "Country (of organization)": "Unknown"]))
    #expect(unknown.entries[0].name == "model-0")
    #expect(unknown.entries[0].openness == nil)
    #expect(unknown.entries[0].developerCountry == nil)
    #expect(try EpochECIParser.parse(eciCSV(["Country (of organization)": "GB"])).entries[0].developerCountry?.countryCode == "GB")

    let tied = try EpochECIParser.parse(eciCSV(["Display name": "Z model", "eci": "169.66666666666666", "Organization": ""]))
    let independent = try #require(tied.entries.first { $0.modelID == "model-0" })
    #expect(independent.organization == nil)
    #expect(tied.entries[0].modelID == "model-1")

}

@Test func epochRejectsPartialOrInvalidData() throws {
    for source in ["", "<html>Blocked</html>", eciCSV(count: 19), eciCSV(["eci": ""]), eciCSV(["eci": "NaN"]),
                   eciCSV(["eci": "Infinity"]), eciCSV(["eci": "100001"]), eciCSV(["Model": "model-1"]), eciCSV(["Model": ""]),
                   eciCSV(["Organization": "Bad\nOrganization"]), eciCSV().replacingOccurrences(of: "Model,Display name", with: "Model,Model"),
                   eciCSV() + "\"unclosed", eciCSV() + "a,b", "ab\"c", "\"a\"bad"] {
        #expect(throws: (any Error).self) { try EpochECIParser.parse(source) }
    }
    #expect(try EpochECIParser.rows("a,b\n\n\"c\",\"d\"\r") == [["a", "b"], ["c", "d"]])
    #expect(try EpochECIParser.rows("a,b") == [["a", "b"]])
}

@Test func epochMetadataMatchesSharedIdentitiesWithoutGuessingVariants() throws {
    for (organization, key) in [("Google DeepMind", "google"), ("Meta AI", "meta"),
                                ("Mistral AI", "mistral"), ("Z.ai (Zhipu AI)", "zai"),
                                ("Microsoft Research", "microsoftai")] {
        let board = try EpochECIParser.parse(eciCSV(["Organization": organization]))
        let row = board.entries[0]
        #expect(OrganizationLogoCatalog.developerKey(organization: row.organization) == key)
        #expect(row.developerCountry?.key == key)
        #expect(OrganizationRegion.country(for: row)?.regionCode == "US")
        #expect(OrganizationLogoCatalog.resolvedKey(organization: organization) == key)
    }
    for (id, country, openness) in [("Qwen2.5-Coder-14B", "CN", ModelOpenness.open),
                                   ("internlm-20b", "CN", .open), ("DeepSeek-Coder-V2-Lite-Base", "CN", .open),
                                   ("Yi-9B", "CN", .open), ("PaLM 2-L", "US", .closed),
                                   ("RedPajama-INCITE-7B-Base", "US", .open)] {
        let board = try EpochECIParser.parse(eciCSV(["Model": id, "Display name": id, "Organization": "",
                                                    "Country (of organization)": "", "Accessibility group": "Other"]))
        #expect(board.entries[0].resolvedOpenness == openness)
        #expect(OrganizationRegion.country(for: board.entries[0])?.regionCode == country)
    }
    let community = LeaderboardEntry(rank: 1, name: "open_llama_7b", score: 10, modelID: "open_llama_7b")
    #expect(community.resolvedOpenness == .open)
    #expect(OrganizationRegion.country(for: community) == nil)
    let preview = LeaderboardEntry(rank: 1, name: "Qwen2.5-Coder-14B-preview", score: 10, modelID: "Qwen2.5-Coder-14B-preview")
    #expect(preview.resolvedOpenness == nil)
    #expect(OrganizationRegion.country(for: preview) == nil)
    let explicit = LeaderboardEntry(rank: 1, name: "Qwen2.5-Coder-14B", score: 10, modelID: "Qwen2.5-Coder-14B", openness: .closed)
    #expect(explicit.resolvedOpenness == .closed)
}

@Test func epochCachedOpennessRepairsExactReleasesAndPreservesExplicitUpdates() {
    for id in ["Gemini 4 Argon", "Qwen 3.6 Max (Preview)", "Mistral Large 4",
               "Qwen 3.5 Plus (hosted 397B-A17B)", "Qwen 3.5 Flash (hosted 35B-A3B)", "Qwen 3.6 Flash"] {
        let cached = LeaderboardEntry(rank: 1, name: id, score: 150, modelID: id)
        #expect(cached.openness == nil)
        #expect(cached.resolvedOpenness == .closed)
        #expect(LeaderboardOpennessFilter.closed.matches(cached))
        #expect(!LeaderboardOpennessFilter.unknown.matches(cached))
        let updated = LeaderboardEntry(rank: 1, name: id, score: 150, modelID: id, openness: .open)
        #expect(updated.resolvedOpenness == .open)
        let variant = LeaderboardEntry(rank: 1, name: id, score: 150, modelID: id + "-finetune")
        #expect(variant.resolvedOpenness == nil)
    }
}
