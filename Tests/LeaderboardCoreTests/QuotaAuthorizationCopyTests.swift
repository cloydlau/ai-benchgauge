import LeaderboardKit
import Foundation
import Testing
@testable import LeaderboardCore

struct QuotaAuthorizationCopyTests {
    @Test func onlyOpenAIsReauthorizationCopyChangesAndTheActionStateStaysIntact() {
        let now = Date()
        for kind in [CCSwitchQuotaKind.officialNote, .xaiOAuth, .claude] {
            let chip = AccountQuotaChip(id: "fixture", shortName: "Fixture", websiteURL: nil,
                kind: kind, isCurrent: true, status: .message(AccountQuotaMessage.reauthRequired))
            let expected = kind == .officialNote ? AccountQuotaMessage.openAIReauthorize : AccountQuotaMessage.reauthRequired
            #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == expected)
            #expect(AccountQuotaFormatting.menuBarText(forChips: [chip])?.quota == expected)
            #expect(chip.status == .message(AccountQuotaMessage.reauthRequired))
            if kind == .officialNote {
                #expect(AccountQuotaFormatting.help(for: chip, now: now).contains(AccountQuotaMessage.openAIReauthorizeHelp))
            }
        }
        #expect(AppLanguage.english.quotaText(AccountQuotaMessage.openAIReauthorize) == "Reauthorize")
        #expect(AccountQuotaMessage.xaiRefreshDeferred == "退出 CC Switch 后同步")
        #expect(AppLanguage.english.quotaText(AccountQuotaMessage.xaiRefreshDeferred) == "Quit CC Switch to sync")
        #expect(AppLanguage.traditionalChinese.quotaText(AccountQuotaMessage.xaiRefreshDeferred) == "退出 CC Switch 後同步")
        #expect(AppLanguage.traditionalChinese.quotaText(AccountQuotaMessage.openAIReauthorize) == "需重新授權")
    }
}
