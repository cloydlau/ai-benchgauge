import Foundation
import XCTest
@testable import LeaderboardCore

final class AppLanguageTests: XCTestCase {
    func testDefaultAndSavedLanguage() {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hans-CN"]), .chinese)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hant-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["ja-JP", "zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["ja-JP"]), .english)
        AppLanguage.chinese.save(to: defaults)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["en-US"]), .chinese)
        AppLanguage.traditionalChinese.save(to: defaults)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["en-US"]), .traditionalChinese)
        AppLanguage.english.save(to: defaults)
        XCTAssertEqual(AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hans-CN"]), .english)
    }

    func testQuotaCopyAndProviderNames() {
        XCTAssertEqual(AppLanguage.english.providerName(.qwen), "Qwen")
        XCTAssertEqual(AppLanguage.chinese.providerName(.zhipu), "GLM")
        XCTAssertEqual(AppLanguage.english.quotaText("7天 72% · 截至9月24日2时"), "7d 72% · Until Sep 24, 02:00")
        XCTAssertEqual(AppLanguage.english.quotaText("7天额度 2天后重置，9月24日 02:00"), "7d quota resets in 2d, Sep 24 02:00")
        XCTAssertEqual(AppLanguage.chinese.quotaText("1个月 6.8%"), "1个月 6.8%")
        XCTAssertEqual(AppLanguage.traditionalChinese.providerName(.zhipu), "GLM")
        XCTAssertEqual(AppLanguage.traditionalChinese.text("Screenshot", "截图"), "截圖")
        XCTAssertEqual(AppLanguage.traditionalChinese.quotaText("7天 72% · 截至9月24日2时"), "7天 72% · 截至9月24日2時")
    }
}
