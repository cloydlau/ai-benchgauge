import Foundation
import Testing
@testable import LeaderboardCore
import LeaderboardKit

struct QuotaParserBoundaryTests {
    private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed) }
    private func windows(_ result: ProviderQuotaParseResult) -> [ParsedQuotaWindow] {
        guard case .windows(let values) = result else { Issue.record("Expected quota windows"); return [] }
        return values
    }

    @Test func malformedBodiesAndNumericWindowsNeverBecomeAnAccountQuota() throws {
        let parsers: [(Data) -> ProviderQuotaParseResult] = [CCSwitchQuotaParsers.parseOpenAIAppServer, CCSwitchQuotaParsers.parseOpenAI, CCSwitchQuotaParsers.parseKimi, CCSwitchQuotaParsers.parseZhipu, CCSwitchQuotaParsers.parseDeepSeek]
        for data in [Data("broken".utf8), try json([]), try json(NSNull())] {
            for parser in parsers { #expect(parser(data) == .rejected) }
        }
        #expect(CCSwitchQuotaParsers.parseOpenAI(try json([:])) == .rejected)
        #expect(CCSwitchQuotaParsers.parseZhipu(try json([:])) == .rejected)
        #expect(CCSwitchQuotaParsers.parseOpenAIAppServer(try json(["rateLimits": ["limitId": "other"]])) == .rejected)
        for value: Any in [NSNull(), true, [:], "nan", "infinity"] {
            let response: [String: Any] = ["rateLimits": ["primary": ["usedPercent": value]]]
            #expect(windows(CCSwitchQuotaParsers.parseOpenAIAppServer(try json(response))).isEmpty)
            #expect(windows(CCSwitchQuotaParsers.parseOpenAI(try json(["rate_limit": ["primary_window": ["used_percent": value]]]))).isEmpty)
        }
        for duration in [-1, Int64.max] {
            #expect(windows(CCSwitchQuotaParsers.parseOpenAIAppServer(try json(["rateLimits": ["secondary": ["usedPercent": 25, "windowDurationMins": duration]]]))).isEmpty)
        }
        let response = try json(["rate_limit": ["primary_window": ["used_percent": 20], "secondary_window": ["used_percent": 30], "custom": ["used_percent": 40]]])
        #expect(windows(CCSwitchQuotaParsers.parseOpenAI(response)).map(\.name) == ["five_hour", "weekly_limit", "custom"])
        for (seconds, expected) in [(2_592_000, "monthly"), (172_800, "2_day"), (7_200, "2_hour")] {
            let data = try json(["rate_limit": ["primary_window": ["used_percent": 0, "limit_window_seconds": seconds, "reset_at": 0]]])
            #expect(windows(CCSwitchQuotaParsers.parseOpenAI(data)).first?.name == expected)
            #expect(windows(CCSwitchQuotaParsers.parseOpenAI(data)).first?.resetsAt == nil)
        }
        #expect(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(try json(["accounts": ["bad": 1, "default": ["account_id": " "]]]), accountID: "fixture") == nil)
        let defaultDurations = windows(CCSwitchQuotaParsers.parseOpenAIAppServer(try json(["rateLimits": ["primary": ["usedPercent": 0], "secondary": ["usedPercent": 0]]])))
        #expect(defaultDurations.map(\.name) == ["five_hour", "weekly_limit"])
    }

    @Test func kimiCountWindowsHandleUnknownDurationsAndUnreliableCounters() throws {
        let fields: [[String: Any]] = [[:], ["limit": 0], ["limit": true], ["limit": NSNull()], ["limit": []], ["limit": " 10 ", "used": " 2 "], ["limit": 10, "used": -1], ["limit": 10, "remaining": 8], ["limit": 10.5, "used": 1], ["used": 2], ["remaining": 2]]
        for detail in fields {
            let result = windows(CCSwitchQuotaParsers.parseKimi(try json(["detail": detail, "limits": [1, [:], ["detail": detail]]])))
            #expect(!result.isEmpty)
            #expect(result.allSatisfy { $0.utilization.isFinite })
        }
        let durations: [Any] = [1, [:], ["duration": 0], ["duration": 1], ["duration": Int.max / 1440 + 1, "timeUnit": "TIME_UNIT_DAY"], ["duration": Int.max, "timeUnit": "TIME_UNIT_DAY"], ["duration": 1, "time_unit": "TIME_UNIT_DAY"], ["durationMinutes": 30, "timeUnit": "TIME_UNIT_MINUTE"], ["duration": 1, "timeUnit": "unknown"], ["duration": 5, "timeUnit": "TIME_UNIT_HOUR"], NSNull()]
        for duration in durations {
            let result = windows(CCSwitchQuotaParsers.parseKimi(try json(["limits": [["detail": ["limit": 10, "used": 2], "window": duration]]])))
            #expect(result.count == 1)
            #expect(result[0].utilization == 20)
        }
        for path in ["quota", "data"] {
            let data = try json([path: ["usages": ["limit_5h": ["used_ratio": "nan"]]], "usage": ["limit": 10, "used": 2]])
            #expect(windows(CCSwitchQuotaParsers.parseKimi(data)).first?.utilization == 20)
        }
        let ratio = ["limit_7d": ["used_ratio": 0]]
        let data = try json(["data": ["quota": ["usages": ratio]], "limits": [["detail": ["limit": 10, "used": 2]]], "usage": ["limit": 10, "used": 1]])
        #expect(windows(CCSwitchQuotaParsers.parseKimi(data)).map(\.name) == ["five_hour", "weekly_limit"])
        let monthlyCount: [String: Any] = ["window": ["duration": 30, "timeUnit": "TIME_UNIT_DAY"], "detail": ["limit": 10, "used": 2]]
        for pools: [String: Any] in [["limit_7d": ["used_ratio": 0.5]], ["limit_month_total": ["used_ratio": 0.5]]] {
            let result = windows(CCSwitchQuotaParsers.parseKimi(try json(["quota": ["usages": pools], "limits": [monthlyCount]])))
            #expect(result.last?.name == "monthly")
            #expect(result.last?.utilization == (pools["limit_month_total"] == nil ? 20 : 50))
        }
    }

    @Test func balanceDefaultsAndSubscriptionRangesRejectBadData() throws {
        let result = CCSwitchQuotaParsers.parseDeepSeek(try json(["balance_infos": [1, [:], ["total_balance": 1, "currency": " "], ["total_balance": 2]]]))
        #expect(result == .balances([.init(currency: "CNY", amount: 1), .init(currency: "CNY", amount: 2)]))
        let invalid = ["short", "2026-10-13 00:00:00/2026-11-13 00:00:00", "xxxx-xx-xx xx:xx:xx-2026-11-13 00:00:00", "2026-10-13 00:00:00-xxxx-xx-xx xx:xx:xx"]
        for range in invalid {
            let object: [String: Any] = ["status": "VALID", "inCurrentPeriod": true, "valid": range]
            #expect(CCSwitchQuotaParsers.parseZhipuSubscription(try json(["data": [object]])) == nil)
        }
        let values = windows(CCSwitchQuotaParsers.parseZhipu(try json(["data": ["limits": [1, [:], ["type": "credit_limit"], ["type": "tokens_limit", "unit": 6, "number": 2]]]])))
        #expect(values.count == 2)
        #expect(values.allSatisfy { $0.name == "credits" && $0.utilization == 0 })
        #expect(CCSwitchQuotaParsers.parseZhipu(try json(["data": [:]])) == .windows([]))
    }

    @Test func scalarNumbersAndInternetDateFractionsStayValidated() {
        #expect(CCSwitchJSON.double(NSNumber(value: Double.nan)) == nil)
        #expect(CCSwitchJSON.double([1]) == nil)
        #expect(CCSwitchJSON.double(nil) == nil)
        #expect(CCSwitchJSON.double(true) == nil)
        #expect(CCSwitchQuotaParsers.exactInt(NSNumber(value: Double.infinity)) == nil)
        #expect(CCSwitchQuotaParsers.shanghaiDate("2026-10-13", format: "yyyy-MM-dd", timeZone: nil) == CCSwitchQuotaParsers.shanghaiDate("2026-10-13", format: "yyyy-MM-dd"))
        for suffix in ["Z", "z", "+00:00", "-00:00"] { #expect(CCSwitchJSON.isoDate("2026-10-13T00:00:00.123456" + suffix) != nil) }
        #expect(CCSwitchJSON.isoDate("2026-10-13T00:00:00.123456?") == nil)
        #expect(CCSwitchJSON.isoDate("2026-10-13T00:00:00.123456") == nil)
    }

    @Test func grpcErrorsAndMalformedFramesStayDistinctFromAuthentication() {
        #expect(GrokBillingParser.classify(httpStatus: 304, grpcStatus: nil) == .failed)
        for message in ["bad-credentials", "unauthenticated", "oauth2 could not be validated", "access token invalid", "access token expired", "access token could not be validated"] {
            #expect(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 7, grpcMessage: message) == .reauth)
        }
        for message in ["timeout", "deadline", "expired"] { #expect(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 1, grpcMessage: message) == .transient) }
        for status in [4, 14] { #expect(GrokBillingParser.classify(httpStatus: 200, grpcStatus: status) == .transient) }
        #expect(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 1, grpcMessage: "cancelled") == .failed)
        #expect(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 7, grpcMessage: "access token unrelated") == .failed)
        #expect(GrokBillingParser.percentDecode("%41%GG%") == "A%GG%")
        let text = Data("grpc-status: 0\r\ninvalid line\r\n\r\ngrpc-message: %41%GG\n".utf8)
        let frame = Data([0x80, 0, 0, 0, UInt8(text.count)]) + text
        #expect(GrokBillingParser.trailerFields(frame) == ["grpc-status": "0", "grpc-message": "A%GG"])
        #expect(GrokBillingParser.trailerFields(Data([0, 0, 0, 0, 10])) == [:])
        let now = Date(timeIntervalSince1970: 1000)
        let payloads: [[UInt8]] = [[8] + Array(repeating: 255, count: 12), [9, 1], [13, 1], [0, 1, 2, 3, 4], [10, 255, 255, 255], [9] + Array(repeating: 0, count: 8), [8, 1, 11, 1], [15, 1, 13, 1, 1, 1, 1], [0, 0, 0, 0, 0, 1], [10, 5, 13, 0, 0, 192, 127]]
        for bytes in payloads {
            let parsed = GrokBillingParser.parse(Data(bytes), now: now)
            #expect(parsed == nil || (parsed!.usedPercent.isFinite && (0...100).contains(parsed!.usedPercent)))
        }
        #expect(GrokBillingParser.parseSubscriptionExpiry(Data("[]".utf8)) == nil)
    }
}
