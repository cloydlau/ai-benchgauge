import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum XAIDeviceLoginError: Error, Equatable, Sendable {
    case invalidResponse, network, expired, denied, cancelled, accountMismatch, accountChanged, storage
}

/// The device code and tokens never leave this actor. Desktop surfaces receive
/// only the browser URL, user-facing code, expiry and an opaque attempt ID.
public struct XAIDeviceLoginAttempt: Sendable {
    public let id: String
    public let authorizationURL: URL
    public let userCode: String
    public let expiresAt: Date
    public let interval: TimeInterval
}

public enum XAIDeviceLoginPoll: Equatable, Sendable {
    case waiting(TimeInterval)
    case connected
}

public actor XAIDeviceLogin {
    private struct Pending {
        let attempt: XAIDeviceLoginAttempt
        let deviceCode: String
        let tokenEndpoint: URL
        let userEndpoint: URL
        let authURL: URL
        let original: XaiAuthFile.Account?
        let originalDefaultID: String?
        var interval: TimeInterval
        var nextPoll: Date
        var polling = false
    }
    private let transport: any AccountQuotaTransport
    private let now: @Sendable () -> Date
    private var pending: Pending?
    private var generation = UUID()

    public init(transport: any AccountQuotaTransport = URLSessionAccountQuotaTransport(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public func start(authFileURL: URL = XaiAuthFile.defaultURL) async throws -> XAIDeviceLoginAttempt {
        try Task.checkCancellation()
        cancel()
        let generation = self.generation
        let initial = try Self.snapshot(at: authFileURL)
        let original = initial.flatMap(XaiAuthFile.selectedAccount)
        let discovery = try await json(request: URLRequest(url: XaiEndpointValidator.discoveryURL, timeoutInterval: 15))
        guard let issuer = discovery["issuer"] as? String, XaiEndpointValidator.isTrustedIssuer(issuer),
              let device = Self.endpoint(discovery["device_authorization_endpoint"]),
              let token = Self.endpoint(discovery["token_endpoint"]),
              let user = Self.endpoint(discovery["userinfo_endpoint"]) else { throw XAIDeviceLoginError.invalidResponse }
        try Task.checkCancellation()
        guard self.generation == generation else { throw XAIDeviceLoginError.cancelled }
        let response = try await json(request: Self.post(device, [
            ("client_id", XaiEndpointValidator.clientID), ("scope", XaiEndpointValidator.scope),
        ]))
        try Task.checkCancellation()
        guard self.generation == generation else { throw XAIDeviceLoginError.cancelled }
        guard let code = Self.nonempty(response["device_code"]), let userCode = Self.nonempty(response["user_code"]),
              let verification = Self.nonempty(response["verification_uri"]),
              let url = Self.authorizationURL(verification, complete: response["verification_uri_complete"] as? String, userCode: userCode),
              let expires = response["expires_in"] as? Double, expires.isFinite, expires > 0, expires <= 86_400 else {
            throw XAIDeviceLoginError.invalidResponse
        }
        let interval = (response["interval"] as? Double) ?? 5
        guard interval.isFinite, interval > 0, interval <= 86_400 else { throw XAIDeviceLoginError.invalidResponse }
        let attempt = XAIDeviceLoginAttempt(id: UUID().uuidString, authorizationURL: url, userCode: userCode,
            expiresAt: now().addingTimeInterval(expires), interval: interval)
        pending = Pending(attempt: attempt, deviceCode: code, tokenEndpoint: token, userEndpoint: user,
            authURL: authFileURL, original: original, originalDefaultID: initial?.defaultAccountID,
            interval: interval, nextPoll: now().addingTimeInterval(interval))
        return attempt
    }

    public func cancel() {
        pending = nil
        generation = UUID()
    }

    public func poll(id: String) async throws -> XAIDeviceLoginPoll {
        try Task.checkCancellation()
        guard var entry = pending, entry.attempt.id == id else { throw XAIDeviceLoginError.cancelled }
        guard now() < entry.attempt.expiresAt else { cancel(); throw XAIDeviceLoginError.expired }
        if entry.polling || now() < entry.nextPoll {
            return .waiting(max(1, entry.nextPoll.timeIntervalSince(now())))
        }
        entry.polling = true
        entry.nextPoll = now().addingTimeInterval(entry.interval)
        pending = entry
        defer { if pending?.attempt.id == id { pending?.polling = false } }
        let response = try await raw(Self.post(entry.tokenEndpoint, [
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ("client_id", XaiEndpointValidator.clientID), ("device_code", entry.deviceCode),
        ]))
        try ensureActive(id)
        guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw XAIDeviceLoginError.invalidResponse
        }
        if let error = payload["error"] as? String {
            switch error {
            case "authorization_pending": return .waiting(entry.interval)
            case "slow_down":
                // RFC 8628: increase every subsequent interval by five seconds.
                pending?.interval += 5
                let interval = pending?.interval ?? entry.interval + 5
                pending?.nextPoll = now().addingTimeInterval(interval)
                return .waiting(interval)
            case "expired_token": cancel(); throw XAIDeviceLoginError.expired
            case "access_denied": cancel(); throw XAIDeviceLoginError.denied
            default: cancel(); throw XAIDeviceLoginError.invalidResponse
            }
        }
        guard (200..<300).contains(response.statusCode),
              let access = Self.nonempty(payload["access_token"]), let refresh = Self.nonempty(payload["refresh_token"]) else {
            cancel(); throw XAIDeviceLoginError.invalidResponse
        }
        var userRequest = URLRequest(url: entry.userEndpoint, timeoutInterval: 15)
        userRequest.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let user = try await json(request: userRequest)
        try ensureActive(id)
        guard let accountID = Self.nonempty(user["sub"]) else { cancel(); throw XAIDeviceLoginError.invalidResponse }
        if let original = entry.original, original.id != accountID {
            cancel(); throw XAIDeviceLoginError.accountMismatch
        }
        try Self.saveLogin(accountID: accountID, refreshToken: refresh,
            login: Self.nonempty(user["email"]) ?? Self.nonempty(user["name"]), entry: entry, now: now())
        cancel()
        return .connected
    }

    private func ensureActive(_ id: String) throws {
        try Task.checkCancellation()
        guard let entry = pending, entry.attempt.id == id else { throw XAIDeviceLoginError.cancelled }
        guard now() < entry.attempt.expiresAt else { cancel(); throw XAIDeviceLoginError.expired }
    }

    private func raw(_ request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        do {
            let response = try await transport.data(for: request)
            guard response.body.count <= 65_536 else { throw XAIDeviceLoginError.invalidResponse }
            return response
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let known = error as? XAIDeviceLoginError { throw known }
            throw XAIDeviceLoginError.network
        }
    }

    private func json(request: URLRequest) async throws -> [String: Any] {
        let response = try await raw(request)
        guard (200..<300).contains(response.statusCode),
              let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw XAIDeviceLoginError.invalidResponse
        }
        return object
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func endpoint(_ value: Any?) -> URL? {
        guard let value = value as? String else { return nil }
        return XaiEndpointValidator.trustedTokenEndpoint(value)
    }

    public static func authorizationURL(_ verification: String, complete: String?, userCode: String) -> URL? {
        func trusted(_ raw: String) -> URLComponents? {
            guard let parts = URLComponents(string: raw), parts.scheme == "https", parts.host == "accounts.x.ai",
                  parts.path == "/oauth2/device", parts.port == nil || parts.port == 443,
                  parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
            return parts
        }
        guard var parts = trusted(verification) else { return nil }
        if let complete {
            guard let full = trusted(complete),
                  full.queryItems?.filter({ $0.name == "user_code" }).map(\.value) == [userCode] else { return nil }
            return full.url
        }
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "user_code" } + [URLQueryItem(name: "user_code", value: userCode)]
        return parts.url
    }

    private static func post(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("cc-switch-xai-oauth", forHTTPHeaderField: "User-Agent")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        return request
    }

    private static func snapshot(at url: URL) throws -> XaiAuthFile.Snapshot? {
        guard FileManager.default.fileExists(atPath: PlatformPaths.fileSystemPath(url)) else { return nil }
        guard let data = try? Data(contentsOf: url), let snapshot = XaiAuthFile.parse(data) else { throw XAIDeviceLoginError.storage }
        return snapshot
    }

    private static func saveLogin(accountID: String, refreshToken: String, login: String?, entry: Pending, now: Date) throws {
        let url = entry.authURL
        let fm = FileManager.default
        let before: Data?
        if fm.fileExists(atPath: PlatformPaths.fileSystemPath(url)) {
            guard let data = try? Data(contentsOf: url), XaiAuthFile.parse(data) != nil else { throw XAIDeviceLoginError.storage }
            before = data
        } else { before = nil }
        let previous = before.flatMap(XaiAuthFile.parse)
        guard previous.flatMap(XaiAuthFile.selectedAccount) == entry.original,
              previous?.defaultAccountID == entry.originalDefaultID else { throw XAIDeviceLoginError.accountChanged }
        var root = before.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? ["version": 1, "accounts": [String: Any]()]
        var accounts = root["accounts"] as? [String: Any] ?? [:]
        let key = accounts.first { key, value in
            ((value as? [String: Any])?["account_id"] as? String ?? key) == accountID
        }?.key ?? accountID
        var account = accounts[key] as? [String: Any] ?? [:]
        account["account_id"] = accountID
        account["refresh_token"] = refreshToken
        account["requires_reauth"] = false
        account["authenticated_at"] = Int64(now.timeIntervalSince1970 * 1000)
        if let login { account["login"] = login }
        accounts[key] = account
        root["accounts"] = accounts
        root["default_account_id"] = accountID
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temp) }
        #if os(Windows)
        let attributes: [FileAttributeKey: Any] = [:]
        #else
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #endif
        guard fm.createFile(atPath: PlatformPaths.fileSystemPath(temp), contents: nil, attributes: attributes) else { throw XAIDeviceLoginError.storage }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            // Do not replace an account selection changed by CC Switch while the browser was open.
            guard (try? Data(contentsOf: url)) == before else { throw XAIDeviceLoginError.accountChanged }
            if before == nil { try fm.moveItem(at: temp, to: url) }
            else { _ = try fm.replaceItemAt(url, withItemAt: temp) }
            #if !os(Windows)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: PlatformPaths.fileSystemPath(url))
            #endif
        } catch let error as XAIDeviceLoginError { throw error }
        catch { throw XAIDeviceLoginError.storage }
    }
}

extension XAIDeviceLoginError {
    public var state: String {
        switch self {
        case .expired: "expired"
        case .denied: "denied"
        case .network: "network"
        case .accountMismatch: "accountMismatch"
        case .accountChanged: "accountChanged"
        case .storage: "storage"
        case .cancelled: "cancelled"
        case .invalidResponse: "failed"
        }
    }
}

public enum XAIDeviceLoginText {
    public static func status(_ state: String, language: AppLanguage) -> String {
        switch state {
        case "starting": language.text("Preparing browser authorization…", "正在准备浏览器授权…")
        case "waiting": language.text("Finish signing in in your browser. Quota refreshes automatically.", "请在浏览器中完成登录，授权成功后自动刷新余量。")
        case "expired": language.text("The code expired. Try again to get a new authorization link.", "授权码已过期，请重试以获取新的授权链接。")
        case "denied": language.text("Authorization was declined. Try again when you are ready.", "授权已被拒绝，可以重新发起登录。")
        case "network": language.text("The auth service could not be reached. Check your connection and try again.", "暂时无法连接授权服务，请检查网络后重试。")
        case "accountMismatch": language.text("This is a different xAI account. Try again with the account used in CC Switch.", "登录的 xAI 账号与 CC Switch 中的账号不同，请使用原账号重试。")
        case "accountChanged": language.text("The shared login changed during authorization. Try again.", "授权期间共用登录发生了变化，请重新登录。")
        case "storage": language.text("Could not save the shared login. Check the CC Switch directory permissions and try again.", "共用登录未能保存，请检查 CC Switch 目录权限后重试。")
        case "saved": language.text("Signed in. BenchGauge refreshes automatically. Restart a running CC Switch to load the shared login.", "登录成功，BenchGauge 会自动刷新余量。如 CC Switch 正在运行，请重启它以载入共用登录。")
        default: language.text("Authorization did not finish. Try again.", "授权未完成，请重试。")
        }
    }
}
