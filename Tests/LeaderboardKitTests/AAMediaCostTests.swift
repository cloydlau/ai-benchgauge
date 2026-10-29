import Foundation
import Testing
@testable import LeaderboardKit

@Test func aaMediaCostsPreserveUnitsAndUnknownValues() throws {
    for kind in [LeaderboardKind.artificialAnalysisTextToImage, .artificialAnalysisTextToVideo] {
        let key = kind == .artificialAnalysisTextToImage ? "pricePer1kImages" : "pricePerMinute"
        let values: [Any] = [210, 0, NSNull(), -1] + Array(repeating: 10, count: 16)
        let records = values.enumerated().map { index, value in
            ["formatted": [:], "values": ["id": "id-\(index)", "name": "Model \(index)", "elo": 1000 - index, key: value]] as [String: Any]
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        let quoted = String(decoding: try JSONSerialization.data(withJSONObject: [json]), as: UTF8.self).dropFirst().dropLast()
        let html = "<script>self.__next_f.push([1,\(quoted)])</script>"
        let board = try kind == .artificialAnalysisTextToImage
            ? HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html)
            : HTMLLeaderboardParser.artificialAnalysisTextToVideo(fromHTML: html)
        #expect(Array(board.entries.prefix(4)).map(\.taskCostUSD) == [kind == .artificialAnalysisTextToImage ? 0.21 : 210, 0, nil, nil])
    }
}
