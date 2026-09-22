import Foundation

/// CC Switch Codex-provider quota, reduced to display data.
///
/// Credential material is extracted only so the menu process can make one
/// request. It must not be logged, cached, or placed on a chip.
public struct CCSwitchProviderRecord: Equatable, Sendable {
    public let id: String
    public let name: String
    public let websiteURL: String?
    public let sortIndex: Int?
    public let createdAt: Int64
    public let isCurrent: Bool
    public let metaJSON: String
    public let settingsConfigJSON: String

    public init(
        id: String,
        name: String,
        websiteURL: String?,
        sortIndex: Int?,
        createdAt: Int64,
        isCurrent: Bool,
        metaJSON: String,
        settingsConfigJSON: String
    ) {
        self.id = id
        self.name = name
        self.websiteURL = websiteURL
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.isCurrent = isCurrent
        self.metaJSON = metaJSON
        self.settingsConfigJSON = settingsConfigJSON
    }
}

public enum CCSwitchQuotaKind: Equatable, Sendable {
    case officialNote
    case kimi
    case zhipu
    case deepseek
    case qwen
    case xaiOAuth
}

public struct CCSwitchQuotaTarget: Equatable, Sendable, Identifiable {
    public let id: String
    public let shortName: String
    public let websiteURL: URL?
    public let kind: CCSwitchQuotaKind
    public let isCurrent: Bool
    /// Present only for key-backed providers. Never display or persist this.
    public let apiKey: String?
    /// OAuth access token for the official Codex provider. Never display or persist this.
    public let accessToken: String?
    /// Account scope used by the official Codex usage endpoint.
    public let accountID: String?
    public let baseURL: String?

    public init(
        id: String,
        shortName: String,
        websiteURL: URL?,
        kind: CCSwitchQuotaKind,
        isCurrent: Bool,
        apiKey: String?,
        baseURL: String?,
        accessToken: String? = nil,
        accountID: String? = nil
    ) {
        self.id = id
        self.shortName = shortName
        self.websiteURL = websiteURL
        self.kind = kind
        self.isCurrent = isCurrent
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.accountID = accountID
        self.baseURL = baseURL
    }
}

public enum AccountQuotaMessage {
    public static let querying = "查询中"
    public static let queryFailed = "查询失败"
    public static let reauthRequired = "需要重新登录"
    public static let notConfigured = "未配置"
    public static let notConfiguredHelp = "没有可用的 API Key，未发起查询"
    public static let notLoggedIn = "未登录"
    public static let notLoggedInHelp = "没有可用的 xAI 登录，未发起查询"
    public static let network = "网络错误"
    public static let officialSummary = "查询中"
    public static let officialHelp = "正在查询 Codex 官方用量"
    public static let emptyBalance = "无可用余额"
    public static let emptyUsage = "暂无本地用量"
}

public struct ParsedQuotaWindow: Equatable, Sendable {
    public let name: String
    public let utilization: Double
    public let resetsAt: Date?

    public init(name: String, utilization: Double, resetsAt: Date?) {
        self.name = name
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct ParsedBalance: Equatable, Sendable {
    public let currency: String
    public let amount: Double

    public init(currency: String, amount: Double) {
        self.currency = currency
        self.amount = amount
    }
}

public struct ParsedUsageWindow: Equatable, Sendable {
    public let name: String
    public let requests: Int
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let costUSD: Double

    public init(
        name: String,
        requests: Int,
        inputTokens: Int64,
        outputTokens: Int64,
        costUSD: Double
    ) {
        self.name = name
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}

public enum ProviderQuotaParseResult: Equatable, Sendable {
    case windows([ParsedQuotaWindow])
    case balances([ParsedBalance])
    case rejected
}

public enum GrokRPCOutcome: Equatable, Sendable {
    case ok
    case reauth
    case transient
    case failed
}

public struct AccountQuotaChip: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Shown before the first response so a failure color does not flash.
        case pending
        case note(text: String, help: String)
        case windows([ParsedQuotaWindow])
        case balances([ParsedBalance])
        case usage([ParsedUsageWindow])
        case message(String)
    }

    public let id: String
    public let shortName: String
    public let websiteURL: URL?
    public let kind: CCSwitchQuotaKind
    public let isCurrent: Bool
    public let status: Status

    public init(
        id: String,
        shortName: String,
        websiteURL: URL?,
        kind: CCSwitchQuotaKind,
        isCurrent: Bool,
        status: Status
    ) {
        self.id = id
        self.shortName = shortName
        self.websiteURL = websiteURL
        self.kind = kind
        self.isCurrent = isCurrent
        self.status = status
    }
}

public enum QuotaTone: Equatable, Sendable {
    case secondary
    case green
    case orange
    case red
}

public struct QuotaTextRun: Equatable, Sendable {
    public let text: String
    public let tone: QuotaTone

    public init(text: String, tone: QuotaTone) {
        self.text = text
        self.tone = tone
    }
}

public enum AccountQuotaFormatting {
    public static func roundedPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(floor(value + 0.5))
    }

    public static func tone(forUtilization value: Double) -> QuotaTone {
        let rounded = roundedPercent(value)
        if rounded >= 90 { return .red }
        if rounded >= 70 { return .orange }
        return .green
    }

    public static func label(forWindowName name: String) -> String {
        switch name {
        case "five_hour": "5小时"
        case "weekly_limit", "seven_day": "7天"
        case "monthly": "每月"
        case "credits": "额度"
        default: name
        }
    }

    /// `diff <= 0` hides the countdown. `hours > 24` drops minutes (`6d2h`).
    /// Exactly 24 hours stays `24h0m`, matching the CC Switch formatter.
    public static func countdown(until resetsAt: Date, now: Date) -> String? {
        let diffMs = resetsAt.timeIntervalSince(now) * 1000
        if diffMs <= 0 { return nil }
        let hours = Int(diffMs / 3_600_000)
        let minutes = Int(diffMs.truncatingRemainder(dividingBy: 3_600_000) / 60_000)
        if hours > 24 {
            return "\(hours / 24)d\(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func balanceAmountText(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%0.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
    }

    /// CC Switch shows the 5-hour window before the weekly window even when the
    /// weekly reset is sooner, or the 5-hour window has no reset time.
    public static func sortedWindows(_ windows: [ParsedQuotaWindow]) -> [ParsedQuotaWindow] {
        windows.enumerated()
            .sorted { lhs, rhs in
                let leftRank = windowRank(lhs.element.name)
                let rightRank = windowRank(rhs.element.name)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                switch (lhs.element.resetsAt, rhs.element.resetsAt) {
                case let (left?, right?) where left != right:
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func windowRank(_ name: String) -> Int {
        switch name {
        case "five_hour": 0
        case "weekly_limit", "seven_day": 1
        case "monthly": 2
        case "credits": 3
        default: 4
        }
    }

    public static func runs(for chip: AccountQuotaChip, now: Date) -> [QuotaTextRun] {
        switch chip.status {
        case .pending:
            return [QuotaTextRun(text: AccountQuotaMessage.querying, tone: .secondary)]
        case let .note(text, _):
            return [QuotaTextRun(text: text, tone: .secondary)]
        case let .message(text):
            return [QuotaTextRun(text: text, tone: .orange)]
        case let .windows(windows):
            let runs = windowRuns(sortedWindows(windows), now: now)
            if runs.isEmpty {
                return [QuotaTextRun(text: AccountQuotaMessage.queryFailed, tone: .orange)]
            }
            return runs
        case let .balances(balances):
            return balanceRuns(balances)
        case let .usage(windows):
            return usageRuns(windows)
        }
    }

    public static func plainSummary(for chip: AccountQuotaChip, now: Date) -> String {
        runs(for: chip, now: now).map(\.text).joined()
    }

    public static func help(for chip: AccountQuotaChip, now: Date) -> String {
        var lines: [String] = []
        if chip.isCurrent {
            lines.append("当前供应商")
        }
        if case let .note(_, help) = chip.status {
            lines.append(help)
        } else {
            let summary = plainSummary(for: chip, now: now)
            if !summary.isEmpty {
                lines.append(summary)
            }
        }
        if let websiteURL = chip.websiteURL {
            lines.append(websiteURL.absoluteString)
        }
        return lines.joined(separator: "\n")
    }

    private static func windowRuns(_ windows: [ParsedQuotaWindow], now: Date) -> [QuotaTextRun] {
        var runs: [QuotaTextRun] = []
        for (index, window) in windows.enumerated() {
            if index > 0 {
                runs.append(QuotaTextRun(text: "  ", tone: .secondary))
            }
            let label = label(forWindowName: window.name)
            runs.append(QuotaTextRun(text: "\(label): ", tone: .secondary))
            runs.append(
                QuotaTextRun(
                    text: "\(roundedPercent(window.utilization))%",
                    tone: tone(forUtilization: window.utilization)
                )
            )
            if let resetsAt = window.resetsAt, let countdown = countdown(until: resetsAt, now: now) {
                runs.append(QuotaTextRun(text: " \(countdown)", tone: .secondary))
            }
        }
        return runs
    }

    private static func balanceRuns(_ balances: [ParsedBalance]) -> [QuotaTextRun] {
        let visible = balances.filter { $0.amount > 0 }
        guard !visible.isEmpty else {
            return [QuotaTextRun(text: AccountQuotaMessage.emptyBalance, tone: .secondary)]
        }
        var runs: [QuotaTextRun] = []
        for (index, balance) in visible.enumerated() {
            if index > 0 {
                runs.append(QuotaTextRun(text: "  ", tone: .secondary))
            }
            runs.append(QuotaTextRun(text: "剩余 ", tone: .secondary))
            runs.append(QuotaTextRun(text: balanceAmountText(balance.amount), tone: .green))
            runs.append(QuotaTextRun(text: " \(balance.currency)", tone: .secondary))
        }
        return runs
    }

    private static func usageRuns(_ windows: [ParsedUsageWindow]) -> [QuotaTextRun] {
        guard !windows.isEmpty else {
            return [QuotaTextRun(text: AccountQuotaMessage.emptyUsage, tone: .secondary)]
        }
        var runs: [QuotaTextRun] = []
        for (index, window) in windows.enumerated() {
            if index > 0 {
                runs.append(QuotaTextRun(text: "  ", tone: .secondary))
            }
            let tokens = compactTokenCount(window.inputTokens + window.outputTokens)
            runs.append(QuotaTextRun(text: "\(window.name): ", tone: .secondary))
            runs.append(QuotaTextRun(text: "\(tokens) tokens", tone: .green))
            runs.append(QuotaTextRun(text: " · \(window.requests)次", tone: .secondary))
            if window.costUSD > 0 {
                runs.append(QuotaTextRun(text: " · $\(balanceAmountText(window.costUSD))", tone: .secondary))
            }
        }
        return runs
    }

    private static func compactTokenCount(_ value: Int64) -> String {
        let absolute = max(value, 0)
        if absolute >= 1_000_000_000 {
            return String(format: "%.1fB", locale: Locale(identifier: "en_US_POSIX"), Double(absolute) / 1_000_000_000)
        }
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", locale: Locale(identifier: "en_US_POSIX"), Double(absolute) / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", locale: Locale(identifier: "en_US_POSIX"), Double(absolute) / 1_000)
        }
        return String(absolute)
    }
}

public enum CCSwitchQuotaCatalog {
    public static func targets(
        from records: [CCSwitchProviderRecord],
        currentProviderID: String?
    ) -> [CCSwitchQuotaTarget] {
        let ordered = records.sorted { lhs, rhs in
            switch (lhs.sortIndex, rhs.sortIndex) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
        }

        var built: [CCSwitchQuotaTarget] = []
        for record in ordered {
            guard let kind = kind(for: record) else { continue }
            let extracted = credentials(from: record.settingsConfigJSON)
            let baseURL = preferredBaseURL(extracted.baseURLs, kind: kind)
            built.append(
                CCSwitchQuotaTarget(
                    id: record.id,
                    shortName: shortName(for: kind),
                    websiteURL: websiteURL(record.websiteURL),
                    kind: kind,
                    isCurrent: record.isCurrent,
                    apiKey: kind == .officialNote || kind == .xaiOAuth ? nil : extracted.apiKey,
                    baseURL: baseURL,
                    accessToken: kind == .officialNote ? extracted.accessToken : nil,
                    accountID: kind == .officialNote ? extracted.accountID : nil
                )
            )
        }

        let explicitIsVisible = currentProviderID.map { id in
            built.contains { $0.id == id }
        } ?? false
        let named = disambiguate(built)
        return named.map { target in
            let isCurrent = explicitIsVisible
                ? target.id == currentProviderID
                : target.isCurrent
            return CCSwitchQuotaTarget(
                id: target.id,
                shortName: target.shortName,
                websiteURL: target.websiteURL,
                kind: target.kind,
                isCurrent: isCurrent,
                apiKey: target.apiKey,
                baseURL: target.baseURL
            )
        }
    }

    public static func zhipuQuotaURL(baseURL: String?) -> URL {
        let host = baseURL?.lowercased().contains("bigmodel.cn") == true
            ? "https://open.bigmodel.cn"
            : "https://api.z.ai"
        return URL(string: "\(host)/api/monitor/usage/quota/limit")!
    }

    private static func kind(for record: CCSwitchProviderRecord) -> CCSwitchQuotaKind? {
        let meta = jsonObject(record.metaJSON)
        let script = meta?["usage_script"] as? [String: Any]
        if (script?["enabled"] as? Bool) == false {
            return nil
        }
        if isXai(meta) {
            return .xaiOAuth
        }
        let template = (script?["templateType"] as? String)?.lowercased()
        let plan = (script?["codingPlanProvider"] as? String)?.lowercased()
        if record.id == "codex-official" || template == "official_subscription" {
            return .officialNote
        }
        if let plan, !plan.isEmpty {
            switch plan {
            case "kimi": return .kimi
            case "zhipu": return .zhipu
            case "qwen", "bailian", "alibaba": return .qwen
            default: return nil
            }
        }
        let bases = credentials(from: record.settingsConfigJSON).baseURLs
        if bases.contains(where: isQwen) { return .qwen }
        if template == "balance" {
            return bases.contains(where: isDeepSeek) ? .deepseek : nil
        }
        if bases.contains(where: isKimi) { return .kimi }
        if bases.contains(where: isZhipu) { return .zhipu }
        if bases.contains(where: isDeepSeek) { return .deepseek }
        return nil
    }

    private static func isXai(_ meta: [String: Any]?) -> Bool {
        if (meta?["providerType"] as? String) == "xai_oauth" {
            return true
        }
        let binding = meta?["authBinding"] as? [String: Any]
        return (binding?["authProvider"] as? String) == "xai_oauth"
    }

    private static func shortName(for kind: CCSwitchQuotaKind) -> String {
        switch kind {
        case .officialNote: "OpenAI"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .xaiOAuth: "xAI"
        case .zhipu: "智谱"
        case .qwen: "千问"
        }
    }

    private static func disambiguate(_ targets: [CCSwitchQuotaTarget]) -> [CCSwitchQuotaTarget] {
        var seen: [String: Int] = [:]
        return targets.map { target in
            let count = seen[target.shortName, default: 0] + 1
            seen[target.shortName] = count
            guard count > 1 else { return target }
            return CCSwitchQuotaTarget(
                id: target.id,
                shortName: "\(target.shortName) \(count)",
                websiteURL: target.websiteURL,
                kind: target.kind,
                isCurrent: target.isCurrent,
                apiKey: target.apiKey,
                baseURL: target.baseURL
            )
        }
    }

    private static func websiteURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private struct ExtractedCredentials {
        var apiKey: String?
        var accessToken: String?
        var accountID: String?
        var baseURLs: [String]
    }

    private static func credentials(from settingsJSON: String) -> ExtractedCredentials {
        guard let root = jsonObject(settingsJSON) else {
            return ExtractedCredentials(apiKey: nil, accessToken: nil, accountID: nil, baseURLs: [])
        }
        let auth = root["auth"] as? [String: Any]
        let apiKey = usableAPIKey(auth?["OPENAI_API_KEY"] as? String)
        let tokens = auth?["tokens"] as? [String: Any]
        let accessToken = usableToken(tokens?["access_token"] as? String)
        let accountID = usableToken(tokens?["account_id"] as? String)
        var extractedBaseURLs: [String] = []
        if let config = root["config"] as? String {
            extractedBaseURLs.append(contentsOf: baseURLs(inTOML: config))
        } else if let config = root["config"] {
            extractedBaseURLs.append(contentsOf: baseURLs(inJSON: config))
        }
        return ExtractedCredentials(
            apiKey: apiKey,
            accessToken: accessToken,
            accountID: accountID,
            baseURLs: extractedBaseURLs
        )
    }

    private static func usableAPIKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("proxy-") {
            return nil
        }
        return trimmed
    }

    private static func usableToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func preferredBaseURL(_ urls: [String], kind: CCSwitchQuotaKind) -> String? {
        let matches = urls.filter { url in
            switch kind {
            case .kimi: isKimi(url)
            case .zhipu: isZhipu(url)
            case .deepseek: isDeepSeek(url)
            case .qwen: isQwen(url)
            case .officialNote, .xaiOAuth: false
            }
        }
        return matches.first ?? urls.first
    }

    private static func isKimi(_ url: String) -> Bool {
        url.lowercased().contains("api.kimi.com/coding")
    }

    private static func isZhipu(_ url: String) -> Bool {
        let url = url.lowercased()
        return url.contains("bigmodel.cn") || url.contains("api.z.ai")
    }

    private static func isDeepSeek(_ url: String) -> Bool {
        url.lowercased().contains("api.deepseek.com")
    }

    private static func isQwen(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("token-plan.") && lowered.contains("maas.aliyuncs.com")
    }

    private static func baseURLs(inTOML config: String) -> [String] {
        config.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            guard let range = trimmed.range(of: #"base_url\s*=\s*["']([^"']+)["']"#, options: .regularExpression) else {
                return nil
            }
            let matched = String(trimmed[range])
            guard let quote = matched.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
            let value = matched[matched.index(after: quote)...].dropLast()
            let url = String(value)
            return isLoopback(url) ? nil : url
        }
    }

    private static func baseURLs(inJSON value: Any) -> [String] {
        var found: [String] = []
        func walk(_ value: Any, key: String?) {
            if key == "base_url", let url = value as? String, !isLoopback(url) {
                found.append(url)
                return
            }
            if let object = value as? [String: Any] {
                for (childKey, child) in object {
                    walk(child, key: childKey)
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, key: nil)
                }
            }
        }
        walk(value, key: nil)
        return found
    }

    private static func isLoopback(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("127.0.0.1")
            || lowered.contains("localhost")
            || lowered.contains("[::1]")
            || lowered.contains("0.0.0.0")
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

public enum XaiEndpointValidator {
    public static let issuer = "https://auth.x.ai"
    public static let discoveryURL = URL(string: "https://auth.x.ai/.well-known/openid-configuration")!
    public static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    public static let scope = "openid profile email offline_access grok-cli:access api:access"
    public static let billingURL = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!

    public static func isTrustedIssuer(_ value: String) -> Bool {
        normalizedIssuer(value) == issuer
    }

    /// Accept the token endpoint only when discovery stays on xAI's auth host.
    public static func trustedTokenEndpoint(_ value: String) -> URL? {
        guard var components = URLComponents(string: value) else { return nil }
        guard components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "auth.x.ai",
              components.port == nil || components.port == 443,
              components.user == nil,
              components.password == nil else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func normalizedIssuer(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }
}

public enum XaiAuthFile {
    public struct Account: Equatable, Sendable {
        public let id: String
        public let requiresReauth: Bool
        public let refreshToken: String
    }

    public struct Snapshot: Equatable, Sendable {
        public let defaultAccountID: String?
        public let accounts: [Account]
    }

    /// Parses the auth file without retaining the login email.
    public static func parse(_ data: Data) -> Snapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAccounts = root["accounts"] as? [String: Any] else { return nil }
        let accounts = rawAccounts.compactMap { key, value -> Account? in
            guard let object = value as? [String: Any],
                  let token = object["refresh_token"] as? String,
                  !token.isEmpty else { return nil }
            let id = (object["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
            return Account(
                id: id,
                requiresReauth: (object["requires_reauth"] as? Bool) ?? false,
                refreshToken: token
            )
        }
        let defaultID = root["default_account_id"] as? String
        return Snapshot(defaultAccountID: defaultID, accounts: accounts)
    }

    public static func selectedAccount(_ snapshot: Snapshot) -> Account? {
        if let defaultID = snapshot.defaultAccountID,
           let match = snapshot.accounts.first(where: { $0.id == defaultID }) {
            return match
        }
        return snapshot.accounts.count == 1 ? snapshot.accounts[0] : nil
    }

    /// Rewrites only `refresh_token` after confirming the file still has the old token.
    /// Does not touch `requires_reauth`.
    public static func replacingRefreshToken(
        in data: Data,
        accountID: String,
        oldToken: String,
        newToken: String
    ) -> Data? {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldToken,
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var accounts = root["accounts"] as? [String: Any] else { return nil }

        let key = accounts.first { candidate, value in
            guard let object = value as? [String: Any] else { return false }
            let id = (object["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? candidate
            return id == accountID
        }?.key
        guard let key, var account = accounts[key] as? [String: Any],
              (account["refresh_token"] as? String) == oldToken else { return nil }
        account["refresh_token"] = trimmed
        accounts[key] = account
        root["accounts"] = accounts
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
    }
}

extension AccountQuotaChip {
    /// Placeholder that never carries an API key.
    public static func placeholder(for target: CCSwitchQuotaTarget) -> AccountQuotaChip {
        let status: Status
        switch target.kind {
        case .officialNote, .kimi, .zhipu, .deepseek, .qwen, .xaiOAuth:
            status = .pending
        }
        return AccountQuotaChip(
            id: target.id,
            shortName: target.shortName,
            websiteURL: target.websiteURL,
            kind: target.kind,
            isCurrent: target.isCurrent,
            status: status
        )
    }
}
