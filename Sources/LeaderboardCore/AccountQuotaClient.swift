import Darwin
import Foundation

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
    }
}

/// Fetches CC Switch Codex quotas. Credential material stays on the request
/// and in this actor's access-token cache. It is not logged or returned.
public actor AccountQuotaClient {
    private let transport: any AccountQuotaTransport
    private let authFileURL: URL
    private let now: @Sendable () -> Date
    private let xaiTokens = XAIAccessTokens()

    public init(
        transport: any AccountQuotaTransport = URLSessionAccountQuotaTransport(),
        authFileURL: URL = XaiAuthFile.defaultURL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.authFileURL = authFileURL
        self.now = now
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
            case .kimi, .zhipu, .deepseek: true
            case .officialNote, .xaiOAuth: false
            }
        }
        async let xaiChips = xaiChips(for: targets, previous: previous, authFileURL: authFileURL)
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
        let resolvedXAI = try await xaiChips
        var byID: [String: AccountQuotaChip] = [:]
        for chip in keyChips + resolvedXAI {
            byID[chip.id] = Self.keepingLastGood(chip, previous: previous)
        }
        return targets.map { target in
            if target.kind == .officialNote {
                return AccountQuotaChip.placeholder(for: target)
            }
            return byID[target.id] ?? Self.chip(target, .failed)
        }
    }

    private func xaiChips(
        for targets: [CCSwitchQuotaTarget],
        previous: [AccountQuotaChip],
        authFileURL: URL
    ) async throws -> [AccountQuotaChip] {
        let xaiTargets = targets.filter { $0.kind == .xaiOAuth }
        guard !xaiTargets.isEmpty else { return [] }
        let failure = try await xaiTokens.billing(
            transport: transport,
            authFileURL: authFileURL,
            now: now()
        )
        return xaiTargets.map { target in
            switch failure {
            case let .windows(windows):
                return AccountQuotaChip(
                    id: target.id,
                    shortName: target.shortName,
                    websiteURL: target.websiteURL,
                    kind: target.kind,
                    isCurrent: target.isCurrent,
                    status: .windows(windows)
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
        guard let apiKey = usableKey(target.apiKey) else {
            return chip(target, .notConfigured)
        }
        guard let request = keyRequest(target, apiKey: apiKey) else {
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
        switch keyFailure(statusCode: response.statusCode) {
        case let reason?:
            return chip(target, reason)
        case nil:
            break
        }
        let parsed: ProviderQuotaParseResult
        switch target.kind {
        case .kimi:
            parsed = CCSwitchQuotaParsers.parseKimi(response.body)
        case .zhipu:
            parsed = CCSwitchQuotaParsers.parseZhipu(response.body)
        case .deepseek:
            parsed = CCSwitchQuotaParsers.parseDeepSeek(response.body)
        case .officialNote, .xaiOAuth:
            return chip(target, .failed)
        }
        return chip(target, parsed: parsed)
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
        case .officialNote, .xaiOAuth:
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if target.kind == .zhipu {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
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
        case .windows, .balances:
            return AccountQuotaChip(
                id: chip.id,
                shortName: chip.shortName,
                websiteURL: chip.websiteURL,
                kind: chip.kind,
                isCurrent: chip.isCurrent,
                status: prior.status
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
        var token: String
        var validUntil: Date
    }

    private var cached: CachedToken?
    private var tokenEndpoint: URL?

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
        return interpretBilling(response, now: now)
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
        if let cached, cached.accountID == account.id, now < cached.validUntil {
            return .token(cached.token)
        }

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
        if let rotated = payload.refreshToken, rotated != account.refreshToken {
            XaiAuthFile.commitRefreshTokenReplacement(
                at: authFileURL,
                accountID: account.id,
                oldToken: account.refreshToken,
                newToken: rotated
            )
        }
        let lifetime = max(payload.expiresIn ?? 3600, 1)
        cached = CachedToken(
            accountID: account.id,
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
                name: GrokBillingParser.tierName(resetsAt: resetsAt, now: now),
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
