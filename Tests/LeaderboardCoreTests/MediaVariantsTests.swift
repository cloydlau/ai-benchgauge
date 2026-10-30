import Foundation
import LeaderboardCore
import Testing

struct MediaVariantsTests {
    @Test func optionsStayWithinSourceAndMedium() {
        #expect(LeaderboardKind.arenaText.mediaVariants == [.arenaText, .arenaTextUncontrolled])
        #expect(LeaderboardKind.codeArenaWebDev.mediaVariants == [.codeArenaWebDev, .codeArenaImageToWebDev])
        #expect(LeaderboardKind.artificialAnalysisImageEditing.mediaVariants == [.artificialAnalysisTextToImage, .artificialAnalysisImageEditing])
        #expect(LeaderboardKind.artificialAnalysisImageToVideo.mediaVariants == [.artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing])
        #expect(LeaderboardKind.arenaVideoEditing.mediaVariants == [.arenaTextToVideo, .arenaImageToVideo, .arenaVideoEditing])
        #expect(LeaderboardKind.arenaTextToImage.mediaVariants == [.arenaTextToImage, .arenaImageEditing, .arenaMultiImageEditing])
        #expect(LeaderboardKind.artificialAnalysisImageEditing.isAAImageCost)
        #expect(LeaderboardKind.artificialAnalysisVideoEditing.isAAVideoCost)
    }
    private func page(_ count: Int, price: String, appendOther: Bool = true) throws -> String {
        let rows: [[String: Any]] = (1...count).map { rank in
            ["formatted": ["rank": rank], "values": ["id": "id-\(rank)", "name": "Model \(rank)",
                "elo": Double(1200 - rank), price: 10.0, "creator": ["name": "Maker"]]]
        }
        let extra: [[String: Any]] = appendOther ? [["formatted": ["rank": 1], "values": ["id": "other", "name": "Other", "elo": 2000.0]]] : []
        let payload = try JSONSerialization.data(withJSONObject: ["entries": rows + extra])
        let escaped = try JSONSerialization.data(withJSONObject: [String(decoding: payload, as: UTF8.self)])
        let encoded = String(decoding: escaped, as: UTF8.self).dropFirst().dropLast()
        return "<script>self.__next_f.push([1,\(encoded)])</script>"
    }

    @Test func sourceRankingAndPricesStaySeparate() throws {
        for (kind, field, count, expected) in [
            (LeaderboardKind.artificialAnalysisImageEditing, "pricePer1kImages", 20, 0.01),
            (.artificialAnalysisImageToVideo, "pricePerMinute", 20, 10.0),
            (.artificialAnalysisVideoEditing, "pricePerMinute", 10, 10.0),
        ] {
            let board = try HTMLLeaderboardParser.artificialAnalysisMediaVariant(fromHTML: page(count, price: field), kind: kind)
            #expect(board.entries.count == count)
            #expect(board.entries.first?.name == "Model 1")
            #expect(board.entries.first?.taskCostUSD == expected)
            #expect(throws: (any Error).self) {
                try HTMLLeaderboardParser.artificialAnalysisMediaVariant(fromHTML: page(count - 1, price: field, appendOther: false), kind: kind)
            }
        }
    }
}
