import Foundation
import Testing
@testable import LeaderboardCore

struct AppLanguageTests {
    @Test
    func testDefaultAndSavedLanguage() {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return recordFailure("Could not create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hans-CN"])) == (.chinese))
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hant-TW"])) == (.traditionalChinese))
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["zh-HK"])) == (.traditionalChinese))
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["en-US"])) == (.english))
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["ja-JP", "zh-TW"])) == (.traditionalChinese))
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["ja-JP"])) == (.english))
        AppLanguage.chinese.save(to: defaults)
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["en-US"])) == (.chinese))
        AppLanguage.traditionalChinese.save(to: defaults)
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["en-US"])) == (.traditionalChinese))
        AppLanguage.english.save(to: defaults)
        #expect((AppLanguage.load(from: defaults, preferredLanguages: ["zh-Hans-CN"])) == (.english))
    }

    @Test
    func testQuotaCopyAndProviderNames() {
        #expect((AppLanguage.english.providerName(.qwen)) == ("Qwen"))
        #expect((AppLanguage.english.quotaText("7天 72% · 至9月24日2时")) == ("7d 72% · to Sep 24, 02:00"))
        #expect((AppLanguage.traditionalChinese.quotaText("7天 72% · 至9月24日2时")) == ("7天 72% · 至9月24日2時"))
        #expect((AppLanguage.chinese.providerName(.zhipu)) == ("GLM"))
        #expect((AppLanguage.english.quotaText("7天 72% · 截至9月24日2时")) == ("7d 72% · Until Sep 24, 02:00"))
        #expect((AppLanguage.english.quotaText("7天额度 2天后重置，9月24日 02:00")) == ("7d quota resets in 2d, Sep 24 02:00"))
        #expect((AppLanguage.chinese.quotaText("1个月 6.8%")) == ("1个月 6.8%"))
        #expect((AppLanguage.english.quotaText("余 ¥12.36")) == ("Balance ¥12.36"))
        #expect((AppLanguage.traditionalChinese.quotaText("余 ¥12.36")) == ("餘 ¥12.36"))
        #expect((AppLanguage.english.quotaText(AccountQuotaMessage.autoRenewing)) == ("Auto-renew"))
        #expect((AppLanguage.traditionalChinese.quotaText(AccountQuotaMessage.autoRenewing)) == ("自動續費"))
        #expect((AppLanguage.traditionalChinese.providerName(.zhipu)) == ("GLM"))
        #expect((AppLanguage.traditionalChinese.text("Screenshot", "截图")) == ("截圖"))
        #expect((AppLanguage.traditionalChinese.quotaText("7天 72% · 截至9月24日2时")) == ("7天 72% · 截至9月24日2時"))
        #expect((AppLanguage.english.quotaText(AccountQuotaMessage.xaiSignInHelp)) == ("Grok sign-in is completed in CC Switch; sign in there"))
        #expect((AppLanguage.chinese.quotaText(AccountQuotaMessage.xaiSignInHelp)) == (AccountQuotaMessage.xaiSignInHelp))
        #expect((AppLanguage.traditionalChinese.quotaText(AccountQuotaMessage.xaiSignInHelp)) == ("Grok 登錄在 CC Switch 中完成，請在 CC Switch 中登錄"))
    }
}
