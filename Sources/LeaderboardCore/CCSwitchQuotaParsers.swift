import Foundation

/// Response-body parsers for CC Switch Codex quota providers.
///
/// These functions never see credentials. Callers map `.rejected` to the
/// fixed "查询失败" string and must not surface raw response text.
public enum CCSwitchQuotaParsers {
    /// Parses the Codex official `backend-api/wham/usage` response.
    public static func parseOpenAI(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data),
              let rateLimit = body["rate_limit"] as? [String: Any] else {
            return .rejected
        }
        var windows: [ParsedQuotaWindow] = []
        for (key, value) in rateLimit {
            guard let object = value as? [String: Any],
                  let used = jsonDouble(object["used_percent"]),
                  used.isFinite else { continue }
            let name: String
            switch key {
            case "primary_window": name = windowName(seconds: jsonInt(object["limit_window_seconds"]) ?? 0, fallback: "five_hour")
            case "secondary_window": name = windowName(seconds: jsonInt(object["limit_window_seconds"]) ?? 0, fallback: "weekly_limit")
            default: name = key
            }
            windows.append(
                ParsedQuotaWindow(
                    name: name,
                    utilization: min(max(used, 0), 100),
                    resetsAt: resetDate(object["reset_at"])
                )
            )
        }
        return .windows(windows)
    }

    public static func parseKimi(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        var windows: [ParsedQuotaWindow] = []
        if let limits = body["limits"] as? [Any] {
            for item in limits {
                guard let object = item as? [String: Any],
                      let detail = object["detail"] as? [String: Any] else { continue }
                windows.append(
                    ParsedQuotaWindow(
                        name: "five_hour",
                        utilization: utilization(limit: detail["limit"], remaining: detail["remaining"]),
                        resetsAt: resetDate(detail["resetTime"])
                    )
                )
            }
        }
        if let usage = body["usage"] as? [String: Any] {
            windows.append(
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: utilization(limit: usage["limit"], remaining: usage["remaining"]),
                    resetsAt: resetDate(usage["resetTime"])
                )
            )
        }
        return .windows(windows)
    }

    public static func parseZhipu(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        if (body["success"] as? Bool) == false {
            return .rejected
        }
        guard let payload = body["data"] as? [String: Any] else { return .rejected }
        return .windows(zhipuWindows(payload))
    }

    public static func parseDeepSeek(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        var balances: [ParsedBalance] = []
        if let infos = body["balance_infos"] as? [Any] {
            for item in infos {
                guard let info = item as? [String: Any] else { continue }
                guard let amount = jsonDouble(info["total_balance"]) else { continue }
                let currency = (info["currency"] as? String).flatMap { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                } ?? "CNY"
                balances.append(ParsedBalance(currency: currency, amount: amount))
            }
        }
        return .balances(balances)
    }

    private static func utilization(limit: Any?, remaining: Any?) -> Double {
        let limitValue = jsonDouble(limit) ?? 1
        let remainingValue = jsonDouble(remaining) ?? 0
        let used = max(limitValue - remainingValue, 0)
        guard limitValue > 0 else { return 0 }
        return (used / limitValue) * 100
    }

    /// ISO 8601 string, or seconds/milliseconds. `<= 0` means no reset.
    private static func resetDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            return isoDate(text)
        }
        guard let number = jsonInt(value), number > 0 else { return nil }
        let milliseconds = number < 1_000_000_000_000 ? number * 1000 : number
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private static func windowName(seconds: Int64, fallback: String) -> String {
        switch seconds {
        case 18_000: return "five_hour"
        case 604_800: return "weekly_limit"
        case 2_592_000: return "monthly"
        default:
            guard seconds > 0 else { return fallback }
            let hours = seconds / 3_600
            return hours >= 24 ? "(hours / 24)_day" : "(hours)_hour"
        }
    }

    private static func zhipuWindows(_ data: [String: Any]) -> [ParsedQuotaWindow] {
        guard let limits = data["limits"] as? [Any] else { return [] }
        var fiveHour: ZhipuEntry?
        var weekly: ZhipuEntry?
        var unclassified: [ZhipuEntry] = []

        for item in limits {
            guard let object = item as? [String: Any] else { continue }
            let type = (object["type"] as? String)?.lowercased() ?? ""
            guard type == "tokens_limit" || type == "credit_limit" else { continue }
            let entry = ZhipuEntry(
                resetMilliseconds: jsonInt(object["nextResetTime"]),
                percentage: jsonDouble(object["percentage"]) ?? 0
            )
            switch zhipuWindow(object) {
            case .fiveHour where fiveHour == nil:
                fiveHour = entry
            case .weekly where weekly == nil:
                weekly = entry
            default:
                unclassified.append(entry)
            }
        }

        // Missing `unit` only. A present unit must not be reordered: the weekly
        // bucket can reset sooner than the 5-hour bucket.
        unclassified.sort { lhs, rhs in
            switch (lhs.resetMilliseconds, rhs.resetMilliseconds) {
            case (nil, nil):
                return false
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case let (left?, right?):
                return left < right
            }
        }
        for entry in unclassified {
            if fiveHour == nil {
                fiveHour = entry
            } else if weekly == nil {
                weekly = entry
            }
        }

        var windows: [ParsedQuotaWindow] = []
        if let fiveHour {
            windows.append(fiveHour.window(named: "five_hour"))
        }
        if let weekly {
            windows.append(weekly.window(named: "weekly_limit"))
        }
        return windows
    }

    private enum ZhipuWindow {
        case fiveHour
        case weekly
    }

    private struct ZhipuEntry {
        var resetMilliseconds: Int64?
        var percentage: Double

        func window(named name: String) -> ParsedQuotaWindow {
            ParsedQuotaWindow(
                name: name,
                utilization: percentage,
                resetsAt: resetMilliseconds.map {
                    Date(timeIntervalSince1970: TimeInterval($0) / 1000)
                }
            )
        }
    }

    /// `unit` 3 is the 5-hour window. `unit` 6 is weekly. Anything else falls
    /// through to the reset-time heuristic.
    private static func zhipuWindow(_ item: [String: Any]) -> ZhipuWindow? {
        guard let unit = jsonInt(item["unit"]) else { return nil }
        switch unit {
        case 3: return .fiveHour
        case 6: return .weekly
        default: return nil
        }
    }
}

public enum GrokBillingParser {
    public struct Snapshot: Equatable, Sendable {
        public let usedPercent: Double
        public let resetsAt: Date?

        public init(usedPercent: Double, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public static func parse(_ data: Data, now: Date) -> Snapshot? {
        let bytes = [UInt8](data)
        var payloads = grpcWebDataFrames(bytes)
        if payloads.isEmpty, looksLikeProtobuf(bytes) {
            payloads = [bytes]
        }
        guard !payloads.isEmpty else { return nil }

        var scan = ProtobufScan()
        for payload in payloads {
            scanProtobuf(payload, depth: 0, path: [], order: 0, scan: &scan)
        }

        let parsedPercent = scan.fixed32
            .filter { field in
                field.path.last == 1
                    && field.value.isFinite
                    && field.value >= 0
                    && field.value <= 100
            }
            .min { lhs, rhs in
                if lhs.path.count != rhs.path.count {
                    return lhs.path.count < rhs.path.count
                }
                return lhs.order < rhs.order
            }
            .map { Double($0.value) }

        let nowSeconds = Int64(now.timeIntervalSince1970)
        let resetCandidates = scan.varints.compactMap { field -> (path: [UInt64], timestamp: Int64)? in
            guard (1_700_000_000...2_100_000_000).contains(field.value) else { return nil }
            let timestamp = Int64(field.value)
            guard timestamp > nowSeconds else { return nil }
            return (field.path, timestamp)
        }
        let exactReset = resetCandidates
            .filter { $0.path == [1, 5, 1] }
            .map(\.timestamp)
            .min()
        let reset = exactReset ?? resetCandidates.map(\.timestamp).min()

        let hasUsagePeriod = scan.varints.contains { field in
            field.path.starts(with: [1, 6])
                || (field.path == [1, 8, 1] && (field.value == 1 || field.value == 2))
        }
        let noUsageYet = parsedPercent == nil
            && scan.fixed32.isEmpty
            && reset != nil
            && hasUsagePeriod
        guard let usedPercent = parsedPercent ?? (noUsageYet ? 0 : nil) else { return nil }
        return Snapshot(
            usedPercent: min(max(usedPercent, 0), 100),
            resetsAt: reset.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    /// Classifies an HTTP status and optional grpc-status before the body is trusted.
    public static func classify(
        httpStatus: Int,
        grpcStatus: Int?,
        grpcMessage: String = ""
    ) -> GrokRPCOutcome {
        if httpStatus == 401 || httpStatus == 403 {
            return .reauth
        }
        if httpStatus == 408 || httpStatus == 429 || (500...599).contains(httpStatus) {
            return .transient
        }
        if let grpcStatus, grpcStatus != 0 {
            return classifyGRPC(status: grpcStatus, message: grpcMessage)
        }
        if !(200...299).contains(httpStatus) {
            return .failed
        }
        return .ok
    }

    public static func tierName(resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "credits" }
        let days = ((resetsAt.timeIntervalSince(now)) / 86_400).rounded()
        let wholeDays = Int(days)
        if (4...12).contains(wholeDays) { return "weekly_limit" }
        if (20...45).contains(wholeDays) { return "monthly" }
        return "credits"
    }

    public static func trailerFields(_ data: Data) -> [String: String] {
        var fields: [String: String] = [:]
        let bytes = [UInt8](data)
        var index = 0
        while index + 5 <= bytes.count {
            let flags = bytes[index]
            let length = Int(UInt32(bytes[index + 1]) << 24
                | UInt32(bytes[index + 2]) << 16
                | UInt32(bytes[index + 3]) << 8
                | UInt32(bytes[index + 4]))
            let start = index + 5
            let end = start + length
            guard end <= bytes.count else { break }
            if flags & 0x80 != 0 {
                let text = String(decoding: bytes[start..<end], as: UTF8.self)
                for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
                    guard let separator = line.firstIndex(of: ":") else { continue }
                    let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                    fields[key] = percentDecode(String(value))
                }
            }
            index = end
        }
        return fields
    }

    public static func percentDecode(_ input: String) -> String {
        var output: [UInt8] = []
        let bytes = Array(input.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count,
               let decoded = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                output.append(decoded)
                index += 3
                continue
            }
            output.append(bytes[index])
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func classifyGRPC(status: Int, message: String) -> GrokRPCOutcome {
        let decoded = percentDecode(message)
        if isAuthFailure(status: status, message: decoded) {
            return .reauth
        }
        if isTransient(status: status, message: decoded) {
            return .transient
        }
        return .failed
    }

    private static func isAuthFailure(status: Int, message: String) -> Bool {
        if status == 16 { return true }
        guard status == 7 else { return false }
        let lower = message.lowercased()
        if lower.contains("bad-credentials") || lower.contains("unauthenticated") {
            return true
        }
        if lower.contains("oauth2"), lower.contains("could not be validated") {
            return true
        }
        if lower.contains("access token"),
           lower.contains("invalid") || lower.contains("expired") || lower.contains("could not be validated") {
            return true
        }
        return false
    }

    private static func isTransient(status: Int, message: String) -> Bool {
        switch status {
        case 4, 14:
            return true
        case 1:
            let lower = message.lowercased()
            return lower.contains("timeout") || lower.contains("deadline") || lower.contains("expired")
        default:
            return false
        }
    }

    private struct Fixed32Field {
        var path: [UInt64]
        var value: Float
        var order: Int
    }

    private struct VarintField {
        var path: [UInt64]
        var value: UInt64
    }

    private struct ProtobufScan {
        var fixed32: [Fixed32Field] = []
        var varints: [VarintField] = []
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt32 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    @discardableResult
    private static func scanProtobuf(
        _ bytes: [UInt8],
        depth: Int,
        path: [UInt64],
        order: Int,
        scan: inout ProtobufScan
    ) -> Int {
        var index = 0
        var nextOrder = order
        while index < bytes.count {
            let fieldStart = index
            guard let key = readVarint(bytes, index: &index), key != 0 else {
                index = fieldStart + 1
                continue
            }
            let fieldNumber = key >> 3
            let wireType = key & 0x07
            var fieldPath = path
            fieldPath.append(fieldNumber)
            switch wireType {
            case 0:
                if let value = readVarint(bytes, index: &index) {
                    scan.varints.append(VarintField(path: fieldPath, value: value))
                } else {
                    index = fieldStart + 1
                }
            case 1:
                guard index + 8 <= bytes.count else { return nextOrder }
                index += 8
            case 2:
                guard let length = readVarint(bytes, index: &index),
                      length <= UInt64(bytes.count - index) else {
                    index = fieldStart + 1
                    continue
                }
                let end = index + Int(length)
                if depth < 4 {
                    nextOrder = scanProtobuf(
                        Array(bytes[index..<end]),
                        depth: depth + 1,
                        path: fieldPath,
                        order: nextOrder,
                        scan: &scan
                    )
                }
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return nextOrder }
                let bits = UInt32(bytes[index])
                    | UInt32(bytes[index + 1]) << 8
                    | UInt32(bytes[index + 2]) << 16
                    | UInt32(bytes[index + 3]) << 24
                scan.fixed32.append(
                    Fixed32Field(path: fieldPath, value: Float(bitPattern: bits), order: nextOrder)
                )
                nextOrder += 1
                index += 4
            default:
                index = fieldStart + 1
            }
        }
        return nextOrder
    }

    private static func grpcWebDataFrames(_ data: [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var index = 0
        while index < data.count {
            guard index + 5 <= data.count else { return [] }
            let flags = data[index]
            let length = Int(UInt32(data[index + 1]) << 24
                | UInt32(data[index + 2]) << 16
                | UInt32(data[index + 3]) << 8
                | UInt32(data[index + 4]))
            let start = index + 5
            let end = start + length
            guard end <= data.count else { return [] }
            if flags & 0x80 == 0 {
                frames.append(Array(data[start..<end]))
            }
            index = end
        }
        return frames
    }

    private static func looksLikeProtobuf(_ data: [UInt8]) -> Bool {
        guard let first = data.first else { return false }
        let fieldNumber = first >> 3
        let wireType = first & 0x07
        return fieldNumber > 0 && (wireType == 0 || wireType == 1 || wireType == 2 || wireType == 5)
    }
}

enum CCSwitchJSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func double(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            let parsed = number.doubleValue
            return parsed.isFinite ? parsed : nil
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func int(_ value: Any?) -> Int64? {
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
    }

    static func isoDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: trimmed)
    }
}

private func jsonObject(_ data: Data) -> [String: Any]? {
    CCSwitchJSON.object(data)
}

private func jsonDouble(_ value: Any?) -> Double? {
    CCSwitchJSON.double(value)
}

private func jsonInt(_ value: Any?) -> Int64? {
    CCSwitchJSON.int(value)
}

private func isoDate(_ text: String) -> Date? {
    CCSwitchJSON.isoDate(text)
}
