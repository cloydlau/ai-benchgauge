import Foundation
import Testing
import LeaderboardKit

@Suite struct ModelsDevAttributionTests {
    @Test func bundledNoticeRetainsTheCompleteUpstreamLicense() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let upstream = try String(contentsOf: root.appendingPathComponent("fc/models-dev-license.txt"), encoding: .utf8)
        #expect(ModelsDevAttribution.licenseText == upstream)
        #expect(ModelsDevAttribution.sourceURL.absoluteString == "https://models.dev")
        #expect(ModelsDevAttribution.credit(language: .chinese) == "模型资料：models.dev")
        #expect(ModelsDevAttribution.credit(language: .traditionalChinese) == "模型資料：models.dev")
    }
}
