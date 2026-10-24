import Foundation
import Testing
@testable import LeaderboardPadUI

struct MobilePullRefreshTests {
    @Test func shortVerticalPullAtTopRefreshesButSmallAndHorizontalDragsDoNot() {
        #expect(MobilePullRefreshPolicy.shouldRefresh(startedAtTop: true, translation: CGSize(width: 4, height: 70)))
        #expect(!MobilePullRefreshPolicy.shouldRefresh(startedAtTop: true, translation: CGSize(width: 0, height: 30)))
        #expect(!MobilePullRefreshPolicy.shouldRefresh(startedAtTop: true, translation: CGSize(width: 100, height: 70)))
        #expect(!MobilePullRefreshPolicy.shouldRefresh(startedAtTop: false, translation: CGSize(width: 0, height: 200)))
        #expect(!MobilePullRefreshPolicy.shouldRefresh(startedAtTop: true, translation: CGSize(width: 0, height: -80)))
    }
}
