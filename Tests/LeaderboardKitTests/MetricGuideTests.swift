import Foundation
import Testing
@testable import LeaderboardKit

@Test func metricGuidePersistsPerEligibleSource() throws {
    let name = "metric-guide-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(!MetricGuide.hasSeen(.artificialAnalysis, defaults: defaults))
    MetricGuide.markSeen(.artificialAnalysis, defaults: defaults)
    MetricGuide.markSeen(.arenaText, defaults: defaults)
    #expect(MetricGuide.hasSeen(.artificialAnalysis, defaults: defaults))
    #expect(!MetricGuide.hasSeen(.arenaText, defaults: defaults))
    #expect(!MetricGuide.hasSeen(.openRouterUsage, defaults: defaults))
    #expect(MetricGuide.hasSeen(.artificialAnalysis, defaults: try #require(UserDefaults(suiteName: name))))
}
