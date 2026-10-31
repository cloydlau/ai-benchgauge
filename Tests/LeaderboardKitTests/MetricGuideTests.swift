import Foundation
import Testing
@testable import LeaderboardKit

@Test func metricGuidePersistsPerEligibleSource() throws {
    let name = "metric-guide-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(!MetricGuide.hasSeen(.artificialAnalysis, defaults: defaults))
    MetricGuide.markSeen(.artificialAnalysis, defaults: defaults)
    let saved = defaults.stringArray(forKey: "metricGuideSeenSources")
    MetricGuide.markSeen(.artificialAnalysis, defaults: defaults)
    #expect(defaults.stringArray(forKey: "metricGuideSeenSources") == saved)
    MetricGuide.markSeen(.arenaText, defaults: defaults)
    #expect(MetricGuide.hasSeen(.artificialAnalysis, defaults: defaults))
    #expect(!MetricGuide.hasSeen(.arenaText, defaults: defaults))
    #expect(!MetricGuide.hasSeen(.openRouterUsage, defaults: defaults))
    #expect(MetricGuide.hasSeen(.artificialAnalysis, defaults: try #require(UserDefaults(suiteName: name))))
}

@Test func metricGuideSwitchLabelSupportsEveryLanguage() {
    #expect(MetricGuide.label(.english) == "Click to switch")
    #expect(MetricGuide.label(.chinese) == "点击切换")
    #expect(MetricGuide.label(.traditionalChinese) == "點擊切換")
}
