import Foundation
import LeaderboardCore
import Testing

struct ModelOpennessTests {
    @Test func licenseClassificationRequiresRecognizedMetadata() {
        #expect(ModelOpenness.fromLicense("Proprietary") == .closed)
        for license in ["MIT", "Apache-2.0", "Apache 2.0", "MiniMax Community License", "minimax-h3-community-license-agreement"] {
            #expect(ModelOpenness.fromLicense(license) == .open)
        }
        for license in [nil, "", "Other", "Unknown", "An unfamiliar commercial license"] {
            #expect(ModelOpenness.fromLicense(license) == nil)
        }
    }

    @Test func oldCachesStayUnknownAndNewMetadataSurvivesRoundTrip() throws {
        let old = Data(#"{"rank":1,"name":"Legacy","score":90}"#.utf8)
        #expect(try JSONDecoder().decode(LeaderboardEntry.self, from: old).openness == nil)
        let entry = LeaderboardEntry(rank: 1, name: "Open model", score: 90, organization: "Maker", openness: .open)
        #expect(try JSONDecoder().decode(LeaderboardEntry.self, from: JSONEncoder().encode(entry)) == entry)
        #expect(CompanyLeaderboard.rank([entry]).first?.entry.openness == nil)
        #expect(ModelOpenness.columnTitle(language: .chinese) == "源码")
        #expect(ModelOpenness.open.title(language: .traditionalChinese) == "開源")
    }

    @Test func parsersPreserveOpenClosedAndMissingSourceFields() throws {
        func html(_ records: [String]) -> String {
            let string = "[" + records.joined(separator: ",") + "]"
            let encoded = String(decoding: try! JSONEncoder().encode(string), as: UTF8.self)
            return "<script>self.__next_f.push([1,\(encoded)])</script>"
        }
        let intelligence = (0..<22).map { i in
            let metadata = i % 3 == 0 ? ",\"isOpenWeights\":true" : i % 3 == 1 ? ",\"isOpenWeights\":false" : ""
            return "{\"name\":\"Model \(i)\",\"intelligenceIndex\":\(100-i)\(metadata)}"
        }
        let media = (0..<22).map { i in
            let metadata = i % 3 == 0 ? ",\"openWeightsUrl\":\"https://huggingface.co/maker/model\"" : i % 3 == 1 ? ",\"openWeightsUrl\":null" : ""
            return "{\"formatted\":{},\"values\":{\"name\":\"Model \(i)\",\"elo\":\(100-i)\(metadata)}}"
        }
        let arena = (0..<22).map { i in
            let license = i % 3 == 0 ? "MIT" : i % 3 == 1 ? "Proprietary" : "Other"
            return "{\"modelDisplayName\":\"Model \(i)\",\"rating\":\(100-i),\"license\":\"\(license)\"}"
        }
        let boards = [
            try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html(intelligence)),
            try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html(media)),
            try HTMLLeaderboardParser.artificialAnalysisTextToVideo(fromHTML: html(media)),
            try HTMLLeaderboardParser.arenaText(fromHTML: html(arena)),
            try HTMLLeaderboardParser.arenaWebDev(fromHTML: html(arena)),
            try HTMLLeaderboardParser.arenaTextToImage(fromHTML: html(arena)),
            try HTMLLeaderboardParser.arenaTextToVideo(fromHTML: html(arena))
        ]
        for board in boards {
            #expect(board.entries[0].openness == .open)
            #expect(board.entries[1].openness == .closed)
            #expect(board.entries[2].openness == nil)
        }
    }
}
