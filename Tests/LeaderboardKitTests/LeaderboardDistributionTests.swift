import Foundation
import Testing
@testable import LeaderboardKit

@Test func distributionCountsModelsAndPreservesUnknownMetadata() throws {
    let entries = [
        LeaderboardEntry(rank: 1, name: "A", score: 10000, organization: "OpenAI", openness: .closed),
        LeaderboardEntry(rank: 2, name: "B", score: 1, organization: "OpenAI", openness: .open),
        LeaderboardEntry(rank: 3, name: "C", score: 0, organization: "Alibaba", openness: .open),
        LeaderboardEntry(rank: 4, name: "D", score: 0, organization: "Unverified community")]
    let stats = LeaderboardDistribution(entries: entries)
    #expect(stats.total == 4)
    #expect(stats.countries.map(\.id) == ["US", "CN", "unknown"])
    #expect(stats.countries.map(\.count) == [2, 1, 1])
    #expect(stats.sources.map(\.count) == [2, 1, 1])
    #expect(stats.sources.map(\.percent) == ["50.0%", "25.0%", "25.0%"])
    #expect(stats.countries.reduce(0) { $0 + $1.count } == stats.total)
    let decoded = try JSONDecoder().decode(LeaderboardDistribution.self, from: JSONEncoder().encode(stats))
    #expect(decoded.countries == stats.countries)
    #expect(decoded.sources == stats.sources)
}

@Test func distributionHasNoInventedPercentagesForMissingData() {
    let empty = LeaderboardDistribution(entries: [])
    #expect(empty.countries.isEmpty)
    #expect(empty.sources.map(\.id) == ["open", "closed"])
    #expect(empty.sources.allSatisfy { $0.percent == "—" && $0.fraction == 0 })
    let known = LeaderboardDistribution(entries: [LeaderboardEntry(rank: 1, name: "Known", score: 90, organization: "OpenAI", openness: .open)])
    #expect(known.countries.map(\.id) == ["US"])
    #expect(known.sources.map(\.id) == ["open", "closed"])
    #expect(known.sources.map(\.count) == [1, 0])
    let unknown = LeaderboardDistribution(entries: [LeaderboardEntry(rank: 1, name: "Community", score: 90)])
    #expect(unknown.countries.first?.id == "unknown")
    #expect(unknown.sources.last?.percent == "100.0%")
}

@Test func distributionCompactsTheCountryTailWithoutDroppingModels() {
    let makers = ["OpenAI", "Alibaba", "Mistral", "Cohere", "Black Forest Labs", "PixVerse", "Upstage", "AI21 Labs"]
    let entries = makers.enumerated().map { LeaderboardEntry(rank: $0.offset + 1, name: "Fixture", score: 1, organization: $0.element) }
    let stats = LeaderboardDistribution(entries: entries)
    #expect(stats.countries.reduce(0) { $0 + $1.count } == entries.count)
    #expect(stats.countries.filter { !["other", "unknown"].contains($0.id) }.count == 5)
    #expect(stats.countries.first { $0.id == "other" }?.count == 3)
}

@Test func distributionLabelsAndTinySharesStayExplicit() {
    for language in AppLanguage.allCases {
        let unknown = LeaderboardDistribution.Slice(id: "unknown", count: 1, total: 1)
        let other = LeaderboardDistribution.Slice(id: "other", count: 1, total: 1)
        let china = LeaderboardDistribution.Slice(id: "CN", count: 1, total: 1)
        #expect(unknown.countryName(language: language) == language.text("Unknown", "未知"))
        #expect(other.countryName(language: language) == language.text("Other", "其他"))
        #expect(china.countryName(language: language) == OrganizationCountry(regionCode: "CN")?.localizedName(language: language))
        #expect(LeaderboardDistribution.Slice(id: "invalid", count: 1, total: 1).countryName(language: language) == "invalid")
        #expect(unknown.sourceName(language: language) == language.text("Unknown", "未知"))
        for openness in [ModelOpenness.open, .closed] {
            #expect(LeaderboardDistribution.Slice(id: openness.rawValue, count: 1, total: 1).sourceName(language: language) == openness.title(language: language))
        }
    }
    #expect(LeaderboardDistribution.Slice(id: "CN", count: 1, total: 10000).percent == "<0.1%")
    #expect(LeaderboardDistribution.Slice(id: "closed", count: 0, total: 10000).percent == "0.0%")
}

#if canImport(SwiftUI)
import SwiftUI

@MainActor @Test func distributionChartsRenderMissingAndMixedMetadataInEveryLanguage() throws {
    let mixed = [
        LeaderboardEntry(rank: 1, name: "A", score: 20, organization: "OpenAI", openness: .closed),
        LeaderboardEntry(rank: 2, name: "B", score: 1, organization: "Alibaba", openness: .open),
        LeaderboardEntry(rank: 3, name: "C", score: 0),
        // Include the compacted country tail as well as missing metadata.
        LeaderboardEntry(rank: 4, name: "D", score: 0, organization: "Cohere"),
        LeaderboardEntry(rank: 5, name: "E", score: 0, organization: "Black Forest Labs"),
        LeaderboardEntry(rank: 6, name: "F", score: 0, organization: "AI21 Labs"),
        LeaderboardEntry(rank: 7, name: "G", score: 0, organization: "Upstage")]
    for language in AppLanguage.allCases {
        for entries in [[], mixed] {
            for title in [nil, "Arena"] as [String?] {
                let view = LeaderboardDistributionCharts(entries: entries, language: language, boardTitle: title)
                    .frame(width: 320)
                let image = try #require(ImageRenderer(content: view).cgImage)
                #expect(image.width == 320)
                #expect(image.height > 150 && image.height < 500)
            }
        }
    }
}
#endif

@Test func desktopColumnTitlesIdentifyEachBoardInEveryLanguage() {
    let expected: [(LeaderboardKind, String, String, String)] = [
        (.artificialAnalysisCodingAgent, "Artificial Analysis Coding", "Artificial Analysis 编程", "Artificial Analysis 編程"),
        (.artificialAnalysisTextToImage, "Artificial Analysis Text to Image", "Artificial Analysis 文生图", "Artificial Analysis 文生圖"),
        (.arenaTextToImage, "Text to Image Arena", "Arena 文生图", "Arena 文生圖"),
        (.artificialAnalysisTextToVideo, "Artificial Analysis Text to Video", "Artificial Analysis 文生视频", "Artificial Analysis 文生影片"),
        (.arenaTextToVideo, "Text to Video Arena", "Arena 文生视频", "Arena 文生影片")]
    for (kind, english, chinese, traditional) in expected {
        #expect(LeaderboardPresentation.columnTitle(kind, language: .english) == english)
        #expect(LeaderboardPresentation.columnTitle(kind, language: .chinese) == chinese)
        #expect(LeaderboardPresentation.columnTitle(kind, language: .traditionalChinese) == traditional)
    }
    #expect(LeaderboardPresentation.columnTitle(.artificialAnalysis, language: .english) == LeaderboardKind.artificialAnalysis.sourceLinkTitle)
}
