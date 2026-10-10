import LeaderboardKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AccountQuotaHTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol AccountQuotaTransport: Sendable {
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse
}

public enum XAIOAuthKeepAliveOutcome: Equatable, Sendable {
    case renewed
    case retry
    case loginRequired
}

public enum XAIOAuthKeepAlivePolicy {
    /// xAI does not disclose its idle-session lifetime. Renew well inside the
    /// reported one-day idle failures, independently of quota refresh activity.
    public static let successInterval: TimeInterval = 6 * 60 * 60
    /// A failed renewal gets a short backoff without making successful logins
    /// refresh hourly.
    public static let failureRetryInterval: TimeInterval = 60 * 60
}

public struct XAIOAuthKeepAliveSchedule: Codable, Equatable, Sendable {
    public var accountID: String?
    public var nextAt: Date
    // Missing in legacy schedules. A policy change makes those schedules due
    // immediately instead of retaining a renewal several days in the future.
    public var renewalInterval: TimeInterval?

    public init(accountID: String? = nil, nextAt: Date) {
        self.accountID = accountID
        self.nextAt = nextAt
        renewalInterval = XAIOAuthKeepAlivePolicy.successInterval
    }
}

public struct XAIOAuthKeepAliveScheduleStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = PlatformPaths.applicationSupport.appending(path: "xai-oauth-keepalive.json")) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public func nextDate(accountID: String?) -> Date? {
        guard let data = try? Data(contentsOf: fileURL),
              let schedule = try? decoder.decode(XAIOAuthKeepAliveSchedule.self, from: data),
              schedule.accountID == accountID,
              schedule.renewalInterval == XAIOAuthKeepAlivePolicy.successInterval else { return nil }
        return schedule.nextAt
    }

    public func save(accountID: String?, nextAt: Date) {
        guard let data = try? encoder.encode(XAIOAuthKeepAliveSchedule(accountID: accountID, nextAt: nextAt)) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            #if !os(Windows)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: PlatformPaths.fileSystemPath(fileURL)
            )
            #endif
        } catch {
            // Persistence is best-effort; an unreadable schedule safely falls back to renewal now.
        }
    }
}

public struct URLSessionAccountQuotaTransport: AccountQuotaTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration,
            delegate: QuotaRedirectRejector(),
            delegateQueue: nil
        )
    }

    public func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        let (body, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            let name = (key as? String) ?? String(describing: key)
            let text = (value as? String) ?? String(describing: value)
            headers[name.lowercased()] = text
        }
        return AccountQuotaHTTPResponse(
            statusCode: http?.statusCode ?? 0,
            headers: headers,
            body: body
        )
    }
}

private final class QuotaRedirectRejector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension XaiAuthFile {
    public static var defaultURL: URL {
        CCSwitchProviderStore.defaultXAIAuthURL
    }

    /// Rewrites `refresh_token` only when the file still contains `oldToken`.
    /// Does not touch `requires_reauth`. The file is left at mode 0600.
    @discardableResult
    public static func commitRefreshTokenReplacement(
        at url: URL,
        accountID: String,
        oldToken: String,
        newToken: String
    ) -> Bool {
        guard let current = try? Data(contentsOf: url),
              let updated = replacingRefreshToken(
                in: current,
                accountID: accountID,
                oldToken: oldToken,
                newToken: newToken
              ) else { return false }

        let tempURL = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let tempPath = tempURL.path(percentEncoded: false)
        #if os(Windows)
        do {
            try updated.write(to: tempURL, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            return true
        } catch { return false }
        #else
        let fd = open(tempPath, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else { return false }

        let wrote = updated.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return updated.isEmpty }
            var offset = 0
            while offset < updated.count {
                let count = write(fd, base.advanced(by: offset), updated.count - offset)
                if count < 0 { return false }
                offset += count
            }
            return fsync(fd) == 0 && fchmod(fd, 0o600) == 0
        }
        close(fd)
        guard wrote else {
            unlink(tempPath)
            return false
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path(percentEncoded: false)
            )
            return true
        } catch {
            unlink(tempPath)
            return false
        }
        #endif
    }
}

/// Fetches CC Switch provider quotas. Credential material stays on the request
/// and in this actor's access-token cache. It is not logged or returned.
/// Official usage prefers an app-managed login when one exists, otherwise
/// uses CC Switch's stored access token. The fallback never reads Codex files.
public actor AccountQuotaClient {
    private let transport: any AccountQuotaTransport
    private let authFileURL: URL
    private let qwenQuotaSource: any QwenQuotaSource
    private let officialQuotaSource: (any OfficialAccountQuotaSource)?
    private let now: @Sendable () -> Date
    private let xaiTokens = XAIAccessTokens()
    private let xaiSubscriptionDateStore: XAISubscriptionDateStore
    private var lastGoodXAISubscriptionDatesByAccountID: [String: Date] = [:]

    public init(
        transport: any AccountQuotaTransport = URLSessionAccountQuotaTransport(),
        authFileURL: URL = XaiAuthFile.defaultURL,
        qwenQuotaSource: any QwenQuotaSource = QwenCLIQuotaSource(),
        officialQuotaSource: (any OfficialAccountQuotaSource)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        xaiSubscriptionDateStore: XAISubscriptionDateStore? = nil
    ) {
        self.transport = transport
        self.authFileURL = authFileURL
        self.qwenQuotaSource = qwenQuotaSource
        self.officialQuotaSource = officialQuotaSource
        self.now = now
        self.xaiSubscriptionDateStore = xaiSubscriptionDateStore ?? (authFileURL == XaiAuthFile.defaultURL
            ? XAISubscriptionDateStore()
            : XAISubscriptionDateStore(fileURL: authFileURL.appendingPathExtension("subscription-dates.json")))
    }

    public func refresh(
        targets: [CCSwitchQuotaTarget],
        previous: [AccountQuotaChip] = [],
        authFileURL: URL? = nil
    ) async throws -> [AccountQuotaChip] {
        let transport = self.transport
        let authFileURL = authFileURL ?? self.authFileURL
        let keyTargets = targets.filter { target in
            switch target.kind {
            case .kimi, .zhipu, .deepseek, .minimax, .stepfun, .blackForestLabs, .luma, .claude, .gemini: true
            case .officialNote, .qwen, .xaiOAuth: false
            }
        }
        let officialTargets = targets.filter { $0.kind == .officialNote }
        let qwenTargets = targets.filter { $0.kind == .qwen }
        async let officialChips = officialChips(for: officialTargets, previous: previous)
        async let xaiChips = xaiChips(for: targets, previous: previous, authFileURL: authFileURL)
        async let qwenPlan = qwenTargets.isEmpty
            ? nil
            : await qwenQuotaSource.loadSummary()
        let keyChips = try await withThrowingTaskGroup(of: AccountQuotaChip.self) { group in
            for target in keyTargets {
                group.addTask {
                    try await Self.queryKeyProvider(target, transport: transport)
                }
            }
            var chips: [AccountQuotaChip] = []
            for try await chip in group {
                chips.append(chip)
            }
            return chips
        }
        let qwenSummary = await qwenPlan
        let resolvedQwenStatus: AccountQuotaChip.Status? = qwenSummary.flatMap { data in
            if let website = QwenWebsiteQuotaParser.parse(data) {
                return .qwenWebsite(website)
            }
            return QwenPlanQuotaParser.parse(data).map(AccountQuotaChip.Status.qwenPlan)
                ?? QwenWebsiteQuotaParser.failureStatus(in: data)
        }
        let qwenFallback = resolvedQwenStatus == nil && !qwenTargets.isEmpty
            ? await qwenQuotaSource.unavailableStatus() : nil
        let qwenChips = qwenTargets.map { target in
            AccountQuotaChip(
                id: target.id,
                shortName: target.shortName,
                modelName: target.modelName,
                websiteURL: target.websiteURL,
                kind: target.kind,
                isCurrent: target.isCurrent,
                status: resolvedQwenStatus ?? qwenFallback ?? .message(AccountQuotaMessage.queryFailed)
            )
        }
        let resolvedOfficial = try await officialChips
        let resolvedXAI = try await xaiChips
        var byID: [String: AccountQuotaChip] = [:]
        for chip in keyChips + resolvedOfficial + resolvedXAI + qwenChips {
            byID[chip.id] = Self.keepingLastGood(chip, previous: previous)
        }
        return targets.compactMap { target in
            if let chip = byID[target.id] {
                return chip
            }
            // No stored official login. Hide it instead of failing or telling
            // the user to install Codex.
            if target.kind == .officialNote,
               CCSwitchQuotaCatalog.usableOfficialAccessToken(target.accessToken) == nil {
                return nil
            }
            return Self.chip(target, .failed)
        }
    }

    /// Rotates the selected xAI login without querying its billing API. The
    /// scheduler uses the returned outcome to distinguish a renewed login from
    /// a transient failure that should be retried.
    public func keepAliveXAI(authFileURL: URL? = nil) async throws -> XAIOAuthKeepAliveOutcome {
        let url = authFileURL ?? self.authFileURL
        switch try await xaiTokens.forceRefresh(
            transport: transport,
            authFileURL: url,
            now: now()
        ) {
        case .token:
            return .renewed
        case let .failure(reason):
            switch reason {
            case .failed, .network:
                return .retry
            case .reauth, .notLoggedIn, .notConfigured:
                return .loginRequired
            }
        }
    }

    /// Accept only an official site's subscription response belonging to the
    /// currently selected OAuth login. Website cookies and tokens stay in the
    /// native browser; only a verified date enters the existing account cache.
    public func captureXAIWebsiteSubscription(_ data: Data, authFileURL: URL? = nil) async throws -> Bool {
        let authURL = authFileURL ?? self.authFileURL
        guard data.count <= 1_048_576,
              case let .account(started) = XAIAccessTokens.readLogin(at: authURL),
              let identity = try await xaiTokens.subscriptionUserID(transport: transport, authFileURL: authURL, now: now()),
              identity.accountID == started.id,
              let end = GrokBillingParser.parseSubscriptionExpiry(data, accountID: identity.userID)?.resetsAt,
              end > now(),
              case let .account(current) = XAIAccessTokens.readLogin(at: authURL),
              current.id == started.id else { return false }
        try xaiSubscriptionDateStore.save(.init(accountID: current.id, periodEnd: end, source: .cached))
        return true
    }

    private func officialChips(
        for targets: [CCSwitchQuotaTarget],
        previous: [AccountQuotaChip]
    ) async throws -> [AccountQuotaChip] {
        try await withThrowingTaskGroup(of: AccountQuotaChip?.self) { group in
            for target in targets {
                group.addTask {
                    if let managed = try await self.officialQuotaSource?.loadQuota(for: target) {
                        return managed
                    }
                    return try await Self.queryOfficial(target, transport: self.transport)
                }
            }
            var chips: [AccountQuotaChip] = []
            for try await chip in group {
                if let chip {
                    chips.append(Self.keepingLastGood(chip, previous: previous))
                }
            }
            return chips
        }
    }

    private func xaiChips(
        for targets: [CCSwitchQuotaTarget],
        previous: [AccountQuotaChip],
        authFileURL: URL
    ) async throws -> [AccountQuotaChip] {
        let xaiTargets = targets.filter { $0.kind == .xaiOAuth }
        guard !xaiTargets.isEmpty else { return [] }
        let accountID: String?
        if case let .account(account) = XAIAccessTokens.readLogin(at: authFileURL) {
            accountID = account.id
        } else { accountID = nil }
        let failure = try await xaiTokens.billing(
            transport: transport,
            authFileURL: authFileURL,
            now: now()
        )
        return xaiTargets.map { target in
            switch failure {
            case let .windows(windows):
                var resolvedWindows = windows
                // Bind stored subscription dates to the same selected login
                // before and after the network calls. A usage reset is never
                // persisted or promoted to a subscription boundary.
                if let accountID,
                   case let .account(account) = XAIAccessTokens.readLogin(at: authFileURL),
                   account.id == accountID {
                    if let end = windows.first(where: { $0.name == ParsedQuotaWindow.planExpiryName })?.resetsAt {
                        lastGoodXAISubscriptionDatesByAccountID[accountID] = end
                        try? xaiSubscriptionDateStore.save(.init(accountID: accountID, periodEnd: end, source: .cached))
                    } else if let saved = xaiSubscriptionDateStore.record(accountID: accountID, now: now()) {
                        resolvedWindows.append(ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName,
                            utilization: 0, resetsAt: saved.periodEnd, dateSource: saved.source))
                    } else if let end = lastGoodXAISubscriptionDatesByAccountID[accountID], end > now() {
                        resolvedWindows.append(ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName,
                            utilization: 0, resetsAt: end, dateSource: .cached))
                        try? xaiSubscriptionDateStore.save(.init(accountID: accountID, periodEnd: end, source: .cached))
                    }
                }
                return AccountQuotaChip(
                    id: target.id,
                    shortName: target.shortName,
                    modelName: target.modelName,
                    websiteURL: target.websiteURL,
                    kind: target.kind,
                    isCurrent: target.isCurrent,
                    status: .windows(resolvedWindows)
                )
            case let .failure(reason):
                return Self.chip(target, reason)
            }
        }
    }

    private static func queryKeyProvider(
        _ target: CCSwitchQuotaTarget,
        transport: any AccountQuotaTransport
    ) async throws -> AccountQuotaChip {
        let credential = [.claude, .gemini].contains(target.kind) ? target.accessToken : (target.accessToken ?? target.apiKey)
        guard let apiKey = usableKey(credential) else {
            return chip(target, .notConfigured)
        }
        guard var request = keyRequest(target, apiKey: apiKey) else {
            return chip(target, .failed)
        }
        if target.kind == .gemini {
            let project: AccountQuotaHTTPResponse
            do { project = try await transport.data(for: request) }
            catch {
                if Self.isCancellation(error) { throw CancellationError() }
                return chip(target, .network)
            }
            if let reason = keyFailure(statusCode: project.statusCode) {
                return chip(target, [401, 403].contains(project.statusCode) ? .reauth : reason)
            }
            guard project.body.count <= 1_048_576,
                  let body = try? JSONSerialization.jsonObject(with: project.body) as? [String: Any] else {
                return chip(target, .failed)
            }
            let raw = body["cloudaicompanionProject"]
            let id = (raw as? String) ?? ((raw as? [String: Any])?["id"] as? String)
            request.url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
            request.httpBody = try? JSONSerialization.data(withJSONObject: id.map { ["project": $0] } ?? [:])
        }
        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            return chip(target, .network)
        }
        guard response.body.count <= 1_048_576 else {
            return chip(target, .failed)
        }
        switch keyFailure(statusCode: response.statusCode) {
        case let reason?:
            return chip(target, target.accessToken != nil && [401, 403].contains(response.statusCode) ? .reauth : reason)
        case nil:
            break
        }
        let parsed: ProviderQuotaParseResult
        switch target.kind {
        case .kimi:
            parsed = CCSwitchQuotaParsers.parseKimi(response.body)
        case .zhipu:
            return try await zhipuChip(
                target,
                apiKey: apiKey,
                body: response.body,
                transport: transport
            )
        case .deepseek:
            parsed = CCSwitchQuotaParsers.parseDeepSeek(response.body)
        case .minimax:
            parsed = LeaderboardQuotaParsers.miniMax(response.body)
        case .stepfun:
            parsed = LeaderboardQuotaParsers.stepFun(response.body)
        case .blackForestLabs:
            parsed = LeaderboardQuotaParsers.blackForestLabs(response.body)
        case .luma:
            parsed = LeaderboardQuotaParsers.luma(response.body)
        case .claude:
            parsed = LeaderboardQuotaParsers.claude(response.body)
        case .gemini:
            parsed = LeaderboardQuotaParsers.gemini(response.body)
        case .officialNote, .qwen, .xaiOAuth:
            return chip(target, .failed)
        }
        return chip(target, parsed: parsed)
    }

    /// Quota success is enough to show the card. A subscription failure keeps
    /// the 5-hour and 7-day windows and simply omits the plan expiry.
    private static func zhipuChip(
        _ target: CCSwitchQuotaTarget,
        apiKey: String,
        body: Data,
        transport: any AccountQuotaTransport
    ) async throws -> AccountQuotaChip {
        // The monitor endpoint reports this account-level error as HTTP 200.
        // Keep a fixed, actionable reason rather than exposing arbitrary upstream text.
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           object["success"] as? Bool == false,
           let message = (object["msg"] ?? object["message"]) as? String,
           message.lowercased().filter({ !$0.isWhitespace }) == "当前用户不存在codingplan" {
            return AccountQuotaChip(id: target.id, shortName: target.shortName, modelName: target.modelName,
                websiteURL: target.websiteURL, kind: target.kind, isCurrent: target.isCurrent,
                status: .note(text: AccountQuotaMessage.glmNoCodingPlan, help: AccountQuotaMessage.glmNoCodingPlanHelp))
        }
        let parsed = CCSwitchQuotaParsers.parseZhipu(body)
        guard case let .windows(quotaWindows) = parsed else {
            return chip(target, parsed: parsed)
        }
        guard !quotaWindows.isEmpty else { return chip(target, .failed) }
        var windows = quotaWindows
        if let expiry = try await zhipuPlanExpiry(target, apiKey: apiKey, transport: transport) {
            windows.append(expiry)
        }
        return chip(target, parsed: .windows(windows))
    }

    private static func zhipuPlanExpiry(
        _ target: CCSwitchQuotaTarget,
        apiKey: String,
        transport: any AccountQuotaTransport
    ) async throws -> ParsedQuotaWindow? {
        let url = CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: target.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            return nil
        }
        guard response.body.count <= 1_048_576, (200...299).contains(response.statusCode) else {
            return nil
        }
        return CCSwitchQuotaParsers.parseZhipuSubscription(response.body)
    }

    /// Returns nil when CC Switch has no usable official login. That is not an
    /// error, and it does not depend on a local Codex install.
    private static func queryOfficial(
        _ target: CCSwitchQuotaTarget,
        transport: any AccountQuotaTransport
    ) async throws -> AccountQuotaChip? {
        guard let accessToken = CCSwitchQuotaCatalog.usableOfficialAccessToken(target.accessToken) else {
            return nil
        }
        guard let request = officialRequest(
            path: "/backend-api/wham/usage",
            accessToken: accessToken,
            accountID: target.accountID
        ) else {
            return chip(target, .failed)
        }
        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            return chip(target, .network)
        }
        guard response.body.count <= 1_048_576 else {
            return chip(target, .failed)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            return chip(target, .reauth)
        }
        guard (200...299).contains(response.statusCode) else {
            return chip(target, .failed)
        }
        guard case let .windows(quotaWindows) = CCSwitchQuotaParsers.parseOpenAI(response.body),
              !quotaWindows.isEmpty else {
            return chip(target, .failed)
        }
        var windows = quotaWindows
        if let expiry = try await officialPlanExpiry(
            accessToken: accessToken,
            accountID: target.accountID,
            transport: transport
        ) {
            windows.append(expiry)
        }
        return AccountQuotaChip(
            id: target.id,
            shortName: target.shortName,
            modelName: target.modelName,
            websiteURL: target.websiteURL,
            kind: target.kind,
            isCurrent: target.isCurrent,
            status: .windows(windows)
        )
    }

    /// Usage success is enough to show the card. A check failure, a missing
    /// account, or a missing `expires_at` omits the plan expiry and does not fail usage.
    /// `renews_at` is not read. No account id means the check is skipped,
    /// because a different account's expiry must not be shown.
    static func officialPlanExpiry(
        accessToken: String,
        accountID: String?,
        transport: any AccountQuotaTransport
    ) async throws -> ParsedQuotaWindow? {
        guard let accountID = usableKey(accountID) else { return nil }
        guard let request = officialRequest(
            path: "/backend-api/accounts/check/v4-2023-04-27",
            accessToken: accessToken,
            accountID: accountID
        ) else {
            return nil
        }
        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            return nil
        }
        guard response.body.count <= 1_048_576, (200...299).contains(response.statusCode) else {
            return nil
        }
        return CCSwitchQuotaParsers.parseOpenAIPlanExpiry(response.body, accountID: accountID)
    }

    private static func officialRequest(
        path: String,
        accessToken: String,
        accountID: String?
    ) -> URLRequest? {
        guard let url = URL(string: "https://chatgpt.com\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = usableKey(accountID) {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        return request
    }


    /// Empty and `proxy-` keys are local placeholders, not credentials to send.
    private static func usableKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("proxy-") {
            return nil
        }
        return trimmed
    }

    private static func keyRequest(_ target: CCSwitchQuotaTarget, apiKey: String) -> URLRequest? {
        let url: URL
        let authorization: String
        switch target.kind {
        case .kimi:
            guard let resolved = URL(string: "https://api.kimi.com/coding/v1/usages") else { return nil }
            url = resolved
            authorization = "Bearer \(apiKey)"
        case .deepseek:
            guard let resolved = URL(string: "https://api.deepseek.com/user/balance") else { return nil }
            url = resolved
            authorization = "Bearer \(apiKey)"
        case .zhipu:
            url = CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: target.baseURL)
            authorization = apiKey
        case .minimax:
            let host = URL(string: target.baseURL ?? "")?.host?.lowercased() == "api.minimax.io"
                ? "api.minimax.io" : "api.minimaxi.com"
            url = URL(string: "https://\(host)/v1/api/openplatform/coding_plan/remains")!
            authorization = "Bearer \(apiKey)"
        case .stepfun:
            url = URL(string: "https://api.stepfun.com/v1/accounts")!
            authorization = "Bearer \(apiKey)"
        case .blackForestLabs:
            url = URL(string: "https://api.bfl.ai/v1/credits")!
            authorization = apiKey
        case .luma:
            url = URL(string: "https://api.lumalabs.ai/dream-machine/v1/credits")!
            authorization = "Bearer \(apiKey)"
        case .claude:
            url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
            authorization = "Bearer \(apiKey)"
        case .gemini:
            url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
            authorization = "Bearer \(apiKey)"
        case .officialNote, .qwen, .xaiOAuth:
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(authorization, forHTTPHeaderField: target.kind == .blackForestLabs ? "x-key" : "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if target.kind == .zhipu {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        }
        if target.kind == .claude {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        if target.kind == .gemini {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8)
        }
        return request
    }

    /// 401/403 on a key provider is a bad key, not an xAI re-login.
    private static func keyFailure(statusCode: Int) -> QuotaFailure? {
        if (200...299).contains(statusCode) { return nil }
        if statusCode == 401 || statusCode == 403 { return .failed }
        if statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode) {
            return .network
        }
        return .failed
    }

    private static func chip(_ target: CCSwitchQuotaTarget, parsed: ProviderQuotaParseResult) -> AccountQuotaChip {
        let status: AccountQuotaChip.Status
        switch parsed {
        case let .windows(windows):
            status = .windows(windows)
        case let .balances(balances):
            status = .balances(balances)
        case .rejected:
            status = .message(AccountQuotaMessage.queryFailed)
        }
        return AccountQuotaChip(
            id: target.id,
            shortName: target.shortName,
            modelName: target.modelName,
            websiteURL: target.websiteURL,
            kind: target.kind,
            isCurrent: target.isCurrent,
            status: status
        )
    }

    private static func chip(_ target: CCSwitchQuotaTarget, _ failure: QuotaFailure) -> AccountQuotaChip {
        let status: AccountQuotaChip.Status
        switch failure {
        case .failed:
            status = .message(AccountQuotaMessage.queryFailed)
        case .reauth:
            status = .message(AccountQuotaMessage.reauthRequired)
        case .network:
            status = .message(AccountQuotaMessage.network)
        case .notConfigured:
            status = .note(
                text: AccountQuotaMessage.notConfigured,
                help: AccountQuotaMessage.notConfiguredHelp
            )
        case .notLoggedIn:
            status = .note(
                text: AccountQuotaMessage.notLoggedIn,
                help: AccountQuotaMessage.notLoggedInHelp
            )
        }
        return AccountQuotaChip(
            id: target.id,
            shortName: target.shortName,
            modelName: target.modelName,
            websiteURL: target.websiteURL,
            kind: target.kind,
            isCurrent: target.isCurrent,
            status: status
        )
    }

    private static func keepingLastGood(
        _ chip: AccountQuotaChip,
        previous: [AccountQuotaChip]
    ) -> AccountQuotaChip {
        guard case .message(let text) = chip.status, text == AccountQuotaMessage.network,
              let prior = previous.first(where: { $0.id == chip.id }) else {
            return chip
        }
        switch prior.status {
        case .windows, .balances, .qwenPlan, .qwenWebsite:
            return AccountQuotaChip(
                id: chip.id,
                shortName: chip.shortName,
                modelName: chip.modelName,
                websiteURL: chip.websiteURL,
                kind: chip.kind,
                isCurrent: chip.isCurrent,
                status: prior.status,
                isStale: true
            )
        case .pending, .note, .message:
            return chip
        }
    }

    fileprivate static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

private enum QuotaFailure: Sendable {
    case failed
    case reauth
    case network
    case notConfigured
    case notLoggedIn
}

private enum XAIBillingResult: Sendable {
    case windows([ParsedQuotaWindow])
    case failure(QuotaFailure)
}

/// Serializes xAI refresh so overlapping quota refreshes share one token exchange.
private actor XAIAccessTokens {
    private struct CachedToken {
        var accountID: String
        var refreshToken: String
        var token: String
        var validUntil: Date
    }

    private var cached: CachedToken?
    private var tokenEndpoint: URL?
    private var inFlightRefresh: (id: UUID, account: XaiAuthFile.Account, url: URL, task: Task<XAITokenResult, Error>)?

    func forceRefresh(
        transport: any AccountQuotaTransport,
        authFileURL: URL,
        now: Date
    ) async throws -> XAITokenResult {
        switch Self.readLogin(at: authFileURL) {
        case .notLoggedIn:
            cached = nil
            return .failure(.notLoggedIn)
        case .reauth:
            cached = nil
            return .failure(.reauth)
        case let .account(account):
            return try await coordinatedRefresh(
                account: account,
                transport: transport,
                authFileURL: authFileURL,
                now: now
            )
        }
    }

    func billing(
        transport: any AccountQuotaTransport,
        authFileURL: URL,
        now: Date
    ) async throws -> XAIBillingResult {
        let access: String
        switch try await accessToken(transport: transport, authFileURL: authFileURL, now: now) {
        case let .token(token):
            access = token
        case let .failure(reason):
            return .failure(reason)
        }

        var request = URLRequest(url: XaiEndpointValidator.billingURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = Data(count: 5)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
        request.setValue("cc-switch", forHTTPHeaderField: "User-Agent")

        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if AccountQuotaClient.isCancellation(error) { throw CancellationError() }
            return .failure(.network)
        }
        let billing = interpretBilling(response, now: now)
        guard case let .windows(usage) = billing else { return billing }
        var subscriptionRequest = URLRequest(url: XaiEndpointValidator.subscriptionsURL, timeoutInterval: 8)
        subscriptionRequest.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        subscriptionRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        subscriptionRequest.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        subscriptionRequest.setValue("ai-benchgauge", forHTTPHeaderField: "User-Agent")
        do {
            let subscription = try await transport.data(for: subscriptionRequest)
            if (200...299).contains(subscription.statusCode), subscription.body.count <= 1_048_576,
               let expiry = GrokBillingParser.parseSubscriptionExpiry(subscription.body) {
                return .windows(usage + [expiry])
            }
        } catch {
            if AccountQuotaClient.isCancellation(error) { throw CancellationError() }
        }
        // An optional subscription failure must not erase the usage result or
        // mislabel its weekly reset as the monthly subscription deadline.
        return billing
    }

    func subscriptionUserID(transport: any AccountQuotaTransport, authFileURL: URL, now: Date) async throws -> (accountID: String, userID: String)? {
        guard case let .account(started) = Self.readLogin(at: authFileURL) else { return nil }
        guard case let .token(access) = try await accessToken(transport: transport, authFileURL: authFileURL, now: now),
              cached?.accountID == started.id, cached?.token == access else { return nil }
        var request = URLRequest(url: XaiEndpointValidator.subscriptionUserURL, timeoutInterval: 10)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.data(for: request)
        guard (200...299).contains(response.statusCode), response.body.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let userID = object["userId"] as? String, !userID.isEmpty else { return nil }
        return (accountID: started.id, userID: userID)
    }

    private func accessToken(
        transport: any AccountQuotaTransport,
        authFileURL: URL,
        now: Date
    ) async throws -> XAITokenResult {
        let account: XaiAuthFile.Account
        switch Self.readLogin(at: authFileURL) {
        case .notLoggedIn:
            cached = nil
            return .failure(.notLoggedIn)
        case .reauth:
            cached = nil
            return .failure(.reauth)
        case let .account(value):
            account = value
        }
        if let cached, cached.accountID == account.id, cached.refreshToken == account.refreshToken, now < cached.validUntil {
            return .token(cached.token)
        }

        return try await coordinatedRefresh(
            account: account,
            transport: transport,
            authFileURL: authFileURL,
            now: now
        )
    }

    private func coordinatedRefresh(
        account: XaiAuthFile.Account,
        transport: any AccountQuotaTransport,
        authFileURL: URL,
        now: Date
    ) async throws -> XAITokenResult {
        if let inFlightRefresh {
            let result = try await inFlightRefresh.task.value
            if inFlightRefresh.account == account, inFlightRefresh.url == authFileURL { return result }
            // Another login/file was being renewed; re-read its current token
            // rather than issuing a request with the pre-await snapshot.
            if self.inFlightRefresh?.id == inFlightRefresh.id { self.inFlightRefresh = nil }
            return try await forceRefresh(transport: transport, authFileURL: authFileURL, now: now)
        }
        // Once rotation starts, finish saving the replacement even if the
        // requesting quota view is cancelled. Both callers await the same task.
        let task = Task {
            try await self.performRefresh(account: account, transport: transport, authFileURL: authFileURL, now: now)
        }
        let id = UUID()
        inFlightRefresh = (id, account, authFileURL, task)
        defer { if inFlightRefresh?.id == id { inFlightRefresh = nil } }
        return try await task.value
    }

    private func performRefresh(
        account: XaiAuthFile.Account,
        transport: any AccountQuotaTransport,
        authFileURL: URL,
        now: Date
    ) async throws -> XAITokenResult {
        let endpoint: URL
        switch try await resolveTokenEndpoint(transport: transport) {
        case let .endpoint(url):
            endpoint = url
        case let .failure(reason):
            return .failure(reason)
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("cc-switch-xai-oauth", forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.formBody([
            ("grant_type", "refresh_token"),
            ("client_id", XaiEndpointValidator.clientID),
            ("refresh_token", account.refreshToken),
            ("scope", XaiEndpointValidator.scope),
        ])

        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if AccountQuotaClient.isCancellation(error) { throw CancellationError() }
            return .failure(.network)
        }
        guard response.body.count <= 1_048_576 else {
            return .failure(.failed)
        }

        switch Self.refreshFailure(statusCode: response.statusCode, body: response.body) {
        case let reason?:
            if reason == .reauth { cached = nil }
            return .failure(reason)
        case nil:
            break
        }
        guard let payload = Self.tokenPayload(response.body) else {
            return .failure(.failed)
        }
        guard case let .account(current) = Self.readLogin(at: authFileURL), current == account else {
            cached = nil
            return .failure(.failed)
        }
        if let rotated = payload.refreshToken, rotated != account.refreshToken {
            guard XaiAuthFile.commitRefreshTokenReplacement(
                at: authFileURL,
                accountID: account.id,
                oldToken: account.refreshToken,
                newToken: rotated
            ) else {
                cached = nil
                return .failure(.failed)
            }
        }
        let lifetime = max(payload.expiresIn ?? 3600, 1)
        cached = CachedToken(
            accountID: account.id,
            refreshToken: payload.refreshToken ?? account.refreshToken,
            token: payload.accessToken,
            validUntil: now.addingTimeInterval(TimeInterval(lifetime - 60))
        )
        return .token(payload.accessToken)
    }

    private func resolveTokenEndpoint(
        transport: any AccountQuotaTransport
    ) async throws -> XAIEndpointResult {
        if let tokenEndpoint { return .endpoint(tokenEndpoint) }
        var request = URLRequest(url: XaiEndpointValidator.discoveryURL, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("cc-switch-xai-oauth", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: AccountQuotaHTTPResponse
        do {
            response = try await transport.data(for: request)
        } catch {
            if AccountQuotaClient.isCancellation(error) { throw CancellationError() }
            return .failure(.network)
        }
        if response.statusCode == 408 || response.statusCode == 429 || (500...599).contains(response.statusCode) {
            return .failure(.network)
        }
        guard (200...299).contains(response.statusCode),
              response.body.count <= 1_048_576,
              let object = CCSwitchJSON.object(response.body),
              let issuer = object["issuer"] as? String,
              XaiEndpointValidator.isTrustedIssuer(issuer),
              let rawEndpoint = object["token_endpoint"] as? String,
              let trusted = XaiEndpointValidator.trustedTokenEndpoint(rawEndpoint) else {
            return .failure(.failed)
        }
        tokenEndpoint = trusted
        return .endpoint(trusted)
    }

    private func interpretBilling(_ response: AccountQuotaHTTPResponse, now: Date) -> XAIBillingResult {
        if response.body.count > 1_048_576 {
            return .failure(.failed)
        }
        let headerStatus = response.header("grpc-status").flatMap(Int.init)
        let headerMessage = GrokBillingParser.percentDecode(response.header("grpc-message") ?? "")
        let headerOutcome = GrokBillingParser.classify(
            httpStatus: response.statusCode,
            grpcStatus: headerStatus,
            grpcMessage: headerMessage
        )
        switch headerOutcome {
        case .reauth:
            cached = nil
            return .failure(.reauth)
        case .transient:
            return .failure(.network)
        case .failed:
            return .failure(.failed)
        case .ok:
            break
        }

        let trailers = GrokBillingParser.trailerFields(response.body)
        if let trailerStatus = trailers["grpc-status"].flatMap(Int.init), trailerStatus != 0 {
            let outcome = GrokBillingParser.classify(
                httpStatus: 200,
                grpcStatus: trailerStatus,
                grpcMessage: trailers["grpc-message"] ?? ""
            )
            switch outcome {
            case .reauth:
                cached = nil
                return .failure(.reauth)
            case .transient:
                return .failure(.network)
            case .failed, .ok:
                return .failure(.failed)
            }
        }
        guard let snapshot = GrokBillingParser.parse(response.body, now: now) else {
            return .failure(.failed)
        }
        let resetsAt = snapshot.resetsAt
        return .windows([
            ParsedQuotaWindow(
                name: snapshot.windowName,
                utilization: snapshot.usedPercent,
                resetsAt: resetsAt
            ),
        ])
    }

    private static func refreshFailure(statusCode: Int, body: Data) -> QuotaFailure? {
        let object = CCSwitchJSON.object(body)
        let invalidBody = object == nil
        if statusCode == 401 || statusCode == 403 || (statusCode == 400 && invalidBody) {
            return .reauth
        }
        if let code = (object?["error"] as? String)?.lowercased(),
           code == "invalid_grant" || code == "invalid_token" {
            return .reauth
        }
        if statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode) {
            return .network
        }
        if !(200...299).contains(statusCode) || object?["error"] != nil {
            return .failed
        }
        return nil
    }

    private struct TokenPayload {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int?
    }

    private static func tokenPayload(_ data: Data) -> TokenPayload? {
        guard let object = CCSwitchJSON.object(data),
              let access = object["access_token"] as? String else { return nil }
        let trimmed = access.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let refresh = (object["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expires = CCSwitchJSON.int(object["expires_in"]).map { Int($0) }
        return TokenPayload(
            accessToken: trimmed,
            refreshToken: refresh.flatMap { $0.isEmpty ? nil : $0 },
            expiresIn: expires
        )
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        let text = fields.map { key, value in
            "\(formEscape(key))=\(formEscape(value))"
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private enum XAILoginRead: Sendable {
    case account(XaiAuthFile.Account)
    case notLoggedIn
    case reauth
}

extension XAIAccessTokens {
    /// A missing or unreadable auth file is "not logged in". `requires_reauth`
    /// is a real login that CC Switch has already marked invalid.
    fileprivate static func readLogin(at url: URL) -> XAILoginRead {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = try? Data(contentsOf: url),
              let snapshot = XaiAuthFile.parse(data),
              let account = XaiAuthFile.selectedAccount(snapshot) else {
            return .notLoggedIn
        }
        if account.requiresReauth {
            return .reauth
        }
        return .account(account)
    }
}

private enum XAITokenResult: Sendable {
    case token(String)
    case failure(QuotaFailure)
}

private enum XAIEndpointResult: Sendable {
    case endpoint(URL)
    case failure(QuotaFailure)
}
