import Foundation
import Testing
@testable import LeaderboardCore

struct OpenAIEntitlementBoundaryTests {
    @Test func unverifiedOrPlaceholderEntitlementsCannotEstablishExpiry() throws {
        let validDate = "2026-11-17T00:00:00Z"
        let cases: [[String: Any]] = [
            ["expires_at": validDate],
            ["has_active_subscription": false, "expires_at": validDate],
            ["has_active_subscription": 1, "expires_at": validDate],
            ["has_active_subscription": "true", "expires_at": validDate],
            ["has_active_subscription": true, "subscription_plan": " ChatGPTFreePlan ", "expires_at": validDate],
            ["has_active_subscription": true, "expires_at": "2999-09-28T13:14:52+00:00"],
            ["has_active_subscription": true, "renews_at": validDate],
        ]
        for entitlement in cases {
            let data = try JSONSerialization.data(withJSONObject: ["accounts": ["account-id": ["entitlement": entitlement]]])
            #expect(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(data, accountID: "account-id") == nil)
        }
    }

    @Test func verifiedBoundaryNeverAdvancesToRenewalDate() throws {
        // Yesterday, today, and tomorrow stay the provider's exact boundary.
        for date in ["2026-10-16T00:00:00Z", "2026-10-17T10:00:00Z", "2026-10-18T00:00:00Z"] {
            let data = try JSONSerialization.data(withJSONObject: ["accounts": ["account-id": ["entitlement": [
                "has_active_subscription": true, "expires_at": date, "renews_at": "2026-11-17T10:00:00Z"
            ]]]])
            let parsed = try #require(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(data, accountID: "account-id"))
            #expect(parsed.resetsAt == ISO8601DateFormatter().date(from: date))
            #expect(!parsed.isAutoRenewing)
        }
    }
}
