import Foundation
import Testing
import LeaderboardKit

@Test func ccByLicenseDialogUsesTheOfficialTextRatherThanAttributionNotices() throws {
    #expect(CCBYLicense.canonicalURL == "https://creativecommons.org/licenses/by/4.0/")
    let english = CCBYLicense.text(language: .english)
    let simplified = CCBYLicense.text(language: .chinese)
    let traditional = CCBYLicense.text(language: .traditionalChinese)
    #expect(english.contains("Attribution 4.0 International"))
    #expect(english.contains("Section 1 -- Definitions."))
    #expect(english.contains("Section 8 -- Interpretation."))
    #expect(simplified.contains("第一条 定义"))
    #expect(simplified.contains("第八条 解释"))
    #expect(traditional.contains("姓名標示 4.0"))
    #expect(traditional.contains("第1條 定義"))
    #expect(traditional.contains("第8條 解釋"))
    for text in [english, simplified, traditional] {
        #expect(!text.contains("Epoch AI"))
        #expect(!text.contains("Arena Leaderboard Dataset"))
        #expect(!text.contains("no Epoch AI endorsement"))
        #expect(!text.contains("无 Epoch AI 背书"))
        #expect(!text.contains("無 Epoch AI 背書"))
        #expect(!text.contains("no Arena endorsement"))
        #expect(!text.contains("无 Arena 背书"))
        #expect(!text.contains("無 Arena 背書"))
    }
    #expect(english != EpochAttribution.fullText(language: .english))
    #expect(english != ArenaAttribution.fullText(language: .english))

    struct Source: Decodable {
        let canonicalURL: String
        let en: String
        let zh: String
        let zhHant: String
        enum CodingKeys: String, CodingKey {
            case canonicalURL, en, zh
            case zhHant = "zh-Hant"
        }
    }
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let file = try Data(contentsOf: root.appendingPathComponent("Sources/LeaderboardKit/Resources/CC-BY-4.0.json"))
    let source = try JSONDecoder().decode(Source.self, from: file)
    #expect(source.canonicalURL == CCBYLicense.canonicalURL)
    #expect(source.en == english)
    #expect(source.zh == simplified)
    #expect(source.zhHant == traditional)
}
