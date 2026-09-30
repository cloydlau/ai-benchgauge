#if canImport(CryptoKit)
import CryptoKit
#elseif os(Windows)
import CPlatformSupport
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OfficialAccountQuotaSource: Sendable {
    /// Nil means this provider has never been connected here. An expired app
    /// login returns a reauth chip, so old CC Switch credentials cannot mask it.
    func loadQuota(for target: CCSwitchQuotaTarget) async throws -> AccountQuotaChip?
}

public struct OpenAILoginAttempt: Sendable {
    public let id: String
    public let authorizationURL: URL
    public init(id: String, authorizationURL: URL) {
        self.id = id
        self.authorizationURL = authorizationURL
    }
}

public actor OpenAIManagedQuotaSource: OfficialAccountQuotaSource {
    private struct Binding: Codable {
        let accountID: String
    }
    private struct Credentials {
        let accountID: String
        let accessToken: String?
    }
    private let rootURL: URL
    private let transport: any AccountQuotaTransport
    private let sessionFactory: @Sendable (URL) -> any OpenAIAccountRPC
    private var sessions: [String: any OpenAIAccountRPC] = [:]
    private var activeLogins: [String: String] = [:]
    private var lastRefresh: [String: Date] = [:]

    public init(rootURL: URL? = nil,
                transport: any AccountQuotaTransport = URLSessionAccountQuotaTransport(),
                sessionFactory: @escaping @Sendable (URL) -> any OpenAIAccountRPC = { OpenAIAppServer(profileURL: $0) }) {
        self.rootURL = rootURL ?? PlatformPaths.applicationSupport.appending(path: "openai", directoryHint: .isDirectory)
        self.transport = transport
        self.sessionFactory = sessionFactory
    }

    public func profileURL(for providerID: String) -> URL {
        #if os(Windows)
        let data = Data(providerID.utf8)
        var digest = [UInt8](repeating: 0, count: 32)
        let ok = data.withUnsafeBytes { bg_sha256($0.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), &digest) }
        precondition(ok != 0, "Windows SHA256 unavailable")
        let key = digest.map { String(format: "%02x", $0) }.joined()
        #else
        let key = SHA256.hash(data: Data(providerID.utf8)).map { String(format: "%02x", $0) }.joined()
        #endif
        return rootURL.appending(path: key, directoryHint: .isDirectory)
    }

    private func session(for providerID: String) -> any OpenAIAccountRPC {
        if let session = sessions[providerID] { return session }
        let session = sessionFactory(profileURL(for: providerID))
        sessions[providerID] = session
        return session
    }

    private func params(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func savedAccountID(for providerID: String) -> String? {
        savedCredentials(for: providerID)?.accountID
    }

    private func savedCredentials(for providerID: String) -> Credentials? {
        let url = profileURL(for: providerID).appending(path: "auth.json")
        guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let id = tokens["account_id"] as? String, !id.isEmpty else { return nil }
        return Credentials(accountID: id, accessToken: CCSwitchQuotaCatalog.usableOfficialAccessToken(tokens["access_token"] as? String))
    }

    public func startLogin(for target: CCSwitchQuotaTarget) async throws -> OpenAILoginAttempt {
        guard target.kind == .officialNote else { throw OpenAIConnectionError.invalidResponse }
        guard activeLogins[target.id] == nil else { throw OpenAIConnectionError.serviceFailed }
        // Reserve before awaiting the helper, so repeated clicks cannot create
        // a second callback server for the same provider.
        activeLogins[target.id] = "starting"
        let server = session(for: target.id)
        do {
            let data = try await server.request("account/login/start", params: params(["type": "chatgpt"]))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["loginId"] as? String,
                  let rawURL = object["authUrl"] as? String,
                  let url = URL(string: rawURL),
                  Self.isTrustedAuthorizationURL(url) else { throw OpenAIConnectionError.invalidResponse }
            try Task.checkCancellation()
            guard activeLogins[target.id] == "starting" else { throw CancellationError() }
            activeLogins[target.id] = id
            return OpenAILoginAttempt(id: id, authorizationURL: url)
        } catch {
            activeLogins.removeValue(forKey: target.id)
            await server.stop()
            throw error
        }
    }

    public static func isTrustedAuthorizationURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && ["auth.openai.com", "chatgpt.com"].contains(url.host?.lowercased() ?? "")
    }

    public func finishLogin(_ attempt: OpenAILoginAttempt, for target: CCSwitchQuotaTarget) async throws {
        let server = session(for: target.id)
        do {
            try await server.waitForLogin(attempt.id)
            try Task.checkCancellation()
            guard activeLogins[target.id] == attempt.id else { throw CancellationError() }
            // The helper writes only into this app's private profile. Confirm
            // the account without exposing its tokens or email to the UI.
            guard let accountID = savedAccountID(for: target.id) else {
                throw OpenAIConnectionError.invalidResponse
            }
            if let expected = target.accountID, !expected.isEmpty, expected != accountID {
                _ = try? await server.request("account/logout", params: params([:]))
                throw OpenAIConnectionError.accountMismatch
            }
            let bindingURL = profileURL(for: target.id).appending(path: "binding.json")
            try JSONEncoder().encode(Binding(accountID: accountID)).write(to: bindingURL, options: .atomic)
            try PlatformPaths.restrictFile(bindingURL, permissions: 0o600)
            lastRefresh.removeValue(forKey: target.id)
            activeLogins.removeValue(forKey: target.id)
            await server.stop()
        } catch {
            activeLogins.removeValue(forKey: target.id)
            await server.stop()
            throw error
        }
    }

    public func cancelLogin(for providerID: String) async {
        guard activeLogins.removeValue(forKey: providerID) != nil,
              let server = sessions[providerID] else { return }
        // Terminating the dedicated service also closes its callback listener
        // and resumes every pending request/waiter, including a starting login.
        await server.stop()
    }

    public func loadQuota(for target: CCSwitchQuotaTarget) async throws -> AccountQuotaChip? {
        guard target.kind == .officialNote else { return nil }
        if activeLogins[target.id] != nil {
            return chip(target, status: .note(text: "等待授权", help: "请在浏览器中完成 OpenAI 授权"))
        }
        let bindingURL = profileURL(for: target.id).appending(path: "binding.json")
        guard FileManager.default.fileExists(atPath: bindingURL.path) else { return nil }
        guard let data = try? Data(contentsOf: bindingURL), let binding = try? JSONDecoder().decode(Binding.self, from: data),
              target.accountID == nil || target.accountID?.isEmpty == true || target.accountID == binding.accountID else {
            return nil
        }
        // A canceled/wrong-account browser flow can replace auth.json before
        // its completion is accepted. Never query that account under an old binding.
        guard savedAccountID(for: target.id) == binding.accountID else {
            return chip(target, status: .message(AccountQuotaMessage.reauthRequired))
        }
        let server = session(for: target.id)
        do {
            let shouldRefresh = lastRefresh[target.id].map { Date().timeIntervalSince($0) >= 600 } ?? true
            let account = try await server.request("account/read", params: params(["refreshToken": shouldRefresh]))
            guard let object = try JSONSerialization.jsonObject(with: account) as? [String: Any],
                  let current = object["account"] as? [String: Any], current["type"] as? String == "chatgpt",
                  savedAccountID(for: target.id) == binding.accountID else {
                await server.stop()
                return chip(target, status: .message(AccountQuotaMessage.reauthRequired))
            }
            if shouldRefresh { lastRefresh[target.id] = Date() }
            var quota: Data
            do {
                quota = try await server.request("account/rateLimits/read", params: params([:]))
            } catch OpenAIConnectionError.reauthRequired {
                // Revocation can occur between the account check and usage.
                _ = try await server.request("account/read", params: params(["refreshToken": true]))
                lastRefresh[target.id] = Date()
                quota = try await server.request("account/rateLimits/read", params: params([:]))
            }
            await server.stop()
            guard case var .windows(windows) = CCSwitchQuotaParsers.parseOpenAIAppServer(quota), !windows.isEmpty else {
                return chip(target, status: .message(AccountQuotaMessage.queryFailed))
            }
            // The account service returns usage resets, not subscription end.
            // Read this profile after refresh so the separate expiry request
            // uses the renewed token for the bound account, never CC Switch's.
            guard let credentials = savedCredentials(for: target.id), credentials.accountID == binding.accountID else {
                return chip(target, status: .message(AccountQuotaMessage.reauthRequired))
            }
            if let token = credentials.accessToken,
               let expiry = try await AccountQuotaClient.officialPlanExpiry(
                   accessToken: token,
                   accountID: binding.accountID,
                   transport: transport
               ) {
                windows.append(expiry)
            }
            return chip(target, status: .windows(windows))
        } catch is CancellationError {
            await server.stop()
            throw CancellationError()
        } catch OpenAIConnectionError.reauthRequired {
            await server.stop()
            lastRefresh.removeValue(forKey: target.id)
            return chip(target, status: .message(AccountQuotaMessage.reauthRequired))
        } catch OpenAIConnectionError.helperMissing {
            await server.stop()
            return chip(target, status: .message(AccountQuotaMessage.reauthRequired))
        } catch {
            await server.stop()
            return chip(target, status: .message(AccountQuotaMessage.network))
        }
    }

    private func chip(_ target: CCSwitchQuotaTarget, status: AccountQuotaChip.Status) -> AccountQuotaChip {
        AccountQuotaChip(id: target.id, shortName: target.shortName, modelName: target.modelName,
                         websiteURL: target.websiteURL,
                         kind: target.kind, isCurrent: target.isCurrent, status: status)
    }
}
