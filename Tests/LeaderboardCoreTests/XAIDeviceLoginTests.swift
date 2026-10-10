import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LeaderboardCore

private final class DeviceLoginClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}
private actor DeviceLoginTransport: AccountQuotaTransport {
    private var replies: [AccountQuotaHTTPResponse]
    private var requests: [URLRequest] = []
    init(_ payloads: [String]) { replies = payloads.map { AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data($0.utf8)) } }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.cannotConnectToHost) }
        let result = replies.removeFirst()
        if result.body == Data("network-error".utf8) { throw URLError(.cannotConnectToHost) }
        return result
    }
    func recorded() -> [URLRequest] { requests }
}

struct XAIDeviceLoginTests {
    private let discovery = #"{"issuer":"https://auth.x.ai","device_authorization_endpoint":"https://auth.x.ai/oauth2/device/code","token_endpoint":"https://auth.x.ai/oauth2/token","userinfo_endpoint":"https://auth.x.ai/oauth2/userinfo"}"#
    private let device = #"{"device_code":"fake-device&secret=one","user_code":"Q2QH-TEST","verification_uri":"https://accounts.x.ai/oauth2/device","expires_in":600,"interval":5}"#
    private let tokens = #"{"access_token":"fake-access-private","refresh_token":"fake-new-refresh-private","expires_in":3600}"#
    private let user = #"{"sub":"account-a","email":"test@example.invalid"}"#
    private let initial = #"{"version":1,"default_account_id":"account-a","other_setting":true,"accounts":{"alias-a":{"account_id":"account-a","login":"Original","refresh_token":"old-refresh","requires_reauth":true,"extra":42},"account-b":{"account_id":"account-b","refresh_token":"keep-other","requires_reauth":false}}}"#

    private func authURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "benchgauge-device-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "xai_oauth_auth.json")
    }
    private func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    @Test func browserURLIsPinnedAndContainsTheCorrectCode() {
        #expect(XAIDeviceLogin.authorizationURL("https://accounts.x.ai/oauth2/device", complete: nil, userCode: "Q2QH-TEST")?.absoluteString == "https://accounts.x.ai/oauth2/device?user_code=Q2QH-TEST")
        for bad in ["http://accounts.x.ai/oauth2/device", "https://evil.example/oauth2/device", "https://accounts.x.ai@evil.example/oauth2/device", "https://accounts.x.ai:8443/oauth2/device", "https://accounts.x.ai/oauth2/other", "https://accounts.x.ai/oauth2/device#fragment"] {
            #expect(XAIDeviceLogin.authorizationURL(bad, complete: nil, userCode: "TEST") == nil)
            #expect(XAIDeviceLogin.authorizationURL("https://accounts.x.ai/oauth2/device", complete: bad, userCode: "TEST") == nil)
        }
        #expect(XAIDeviceLogin.authorizationURL("https://accounts.x.ai/oauth2/device", complete: "https://accounts.x.ai/oauth2/device?user_code=WRONG", userCode: "TEST") == nil)
        #expect(XAIDeviceLogin.authorizationURL("https://accounts.x.ai/oauth2/device", complete: "https://accounts.x.ai/oauth2/device?user_code=TEST&user_code=TEST", userCode: "TEST") == nil)
    }

    @Test func completesLoginInTheSharedFileWithoutPersistingDeviceOrAccessTokens() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let transport = DeviceLoginTransport([discovery, device, tokens, user])
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let attempt = try await login.start(authFileURL: url)
        #expect(attempt.authorizationURL.absoluteString == "https://accounts.x.ai/oauth2/device?user_code=Q2QH-TEST")
        #expect(attempt.userCode == "Q2QH-TEST")
        #expect(try await login.poll(id: attempt.id) == .waiting(5))
        #expect(await transport.recorded().count == 2)
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .connected)
        let data = try Data(contentsOf: url)
        let snapshot = try #require(XaiAuthFile.parse(data))
        #expect(snapshot.defaultAccountID == "account-a")
        #expect(XaiAuthFile.selectedAccount(snapshot)?.refreshToken == "fake-new-refresh-private")
        #expect(XaiAuthFile.selectedAccount(snapshot)?.requiresReauth == false)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("fake-access-private"))
        #expect(!text.contains("fake-device"))
        #expect(!text.contains("Q2QH-TEST"))
        let requests = await transport.recorded()
        #expect(requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer fake-access-private")
        #expect(String(decoding: requests[2].httpBody!, as: UTF8.self).contains("device_code=fake-device%26secret%3Done"))
        #if !os(Windows)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #endif
    }

    @Test func reauthClearsOnlyTheSameAccountAndPreservesOtherAccountsAndMetadata() async throws {
        let url = try authURL(); defer { cleanup(url) }
        try Data(initial.utf8).write(to: url)
        let clock = DeviceLoginClock()
        let login = XAIDeviceLogin(transport: DeviceLoginTransport([discovery, device, tokens, user]), now: { clock.now() })
        let attempt = try await login.start(authFileURL: url)
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .connected)
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let accounts = try #require(root["accounts"] as? [String: [String: Any]])
        #expect(accounts.count == 2)
        #expect(accounts["alias-a"]?["extra"] as? Int == 42)
        #expect(accounts["alias-a"]?["requires_reauth"] as? Bool == false)
        #expect(accounts["account-b"]?["refresh_token"] as? String == "keep-other")
        #expect(root["other_setting"] as? Bool == true)
    }

    @Test func refusesADifferentBrowserAccountWithoutOverwritingTheExistingLogin() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let original = Data(initial.utf8); try original.write(to: url)
        let clock = DeviceLoginClock()
        let login = XAIDeviceLogin(transport: DeviceLoginTransport([discovery, device, tokens, #"{"sub":"different-account"}"#]), now: { clock.now() })
        let attempt = try await login.start(authFileURL: url); clock.advance(5)
        await #expect(throws: XAIDeviceLoginError.accountMismatch) { try await login.poll(id: attempt.id) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func pendingAndSlowDownRespectTheServersPollingCadence() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let transport = DeviceLoginTransport([discovery, device, #"{"error":"authorization_pending"}"#, #"{"error":"slow_down"}"#, tokens, user])
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let attempt = try await login.start(authFileURL: url); clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .waiting(5))
        #expect(try await login.poll(id: attempt.id) == .waiting(5))
        #expect(await transport.recorded().count == 3)
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .waiting(10))
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .waiting(5))
        #expect(await transport.recorded().count == 4)
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .connected)
    }

    @Test(arguments: ["access_denied", "expired_token"])
    func terminalServerErrorsCannotKeepPolling(_ code: String) async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let transport = DeviceLoginTransport([discovery, device, "{\"error\":\"\(code)\"}"])
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let attempt = try await login.start(authFileURL: url); clock.advance(5)
        await #expect(throws: code == "access_denied" ? XAIDeviceLoginError.denied : .expired) { try await login.poll(id: attempt.id) }
        await #expect(throws: XAIDeviceLoginError.cancelled) { try await login.poll(id: attempt.id) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await transport.recorded().count == 3)
    }

    @Test func cancellationAndLocalExpiryNeverWriteOrSendAnotherRequest() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let transport = DeviceLoginTransport([discovery, device, discovery, device])
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let first = try await login.start(authFileURL: url)
        await login.cancel()
        await #expect(throws: XAIDeviceLoginError.cancelled) { try await login.poll(id: first.id) }
        let second = try await login.start(authFileURL: url)
        clock.advance(600)
        await #expect(throws: XAIDeviceLoginError.expired) { try await login.poll(id: second.id) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await transport.recorded().count == 4)
    }

    @Test func aTransientPollNetworkFailureCanRetryWithinTheSameAttempt() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let transport = DeviceLoginTransport([discovery, device, "network-error", tokens, user])
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let attempt = try await login.start(authFileURL: url); clock.advance(5)
        await #expect(throws: XAIDeviceLoginError.network) { try await login.poll(id: attempt.id) }
        clock.advance(5)
        #expect(try await login.poll(id: attempt.id) == .connected)
    }

    @Test func discoveryCannotRedirectCredentialsToAnotherHost() async throws {
        let url = try authURL(); defer { cleanup(url) }
        for key in ["device_authorization_endpoint", "token_endpoint", "userinfo_endpoint"] {
            var payload = try #require(JSONSerialization.jsonObject(with: Data(discovery.utf8)) as? [String: Any])
            payload[key] = "https://evil.example/oauth2/steal"
            let transport = DeviceLoginTransport([String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)])
            let login = XAIDeviceLogin(transport: transport)
            await #expect(throws: XAIDeviceLoginError.invalidResponse) { try await login.start(authFileURL: url) }
            #expect(await transport.recorded().count == 1)
        }
    }

    @Test func missingRefreshTokenOrAccountIdentityNeverCreatesAnAuthFile() async throws {
        let url = try authURL(); defer { cleanup(url) }
        for replies in [[discovery, device, #"{"access_token":"fake-access-private"}"#], [discovery, device, tokens, #"{"email":"test@example.invalid"}"#]] {
            let clock = DeviceLoginClock()
            let login = XAIDeviceLogin(transport: DeviceLoginTransport(replies), now: { clock.now() })
            let attempt = try await login.start(authFileURL: url); clock.advance(5)
            await #expect(throws: XAIDeviceLoginError.invalidResponse) { try await login.poll(id: attempt.id) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func aLoginChangedInCCSwitchDuringAuthorizationCannotBeOverwritten() async throws {
        let url = try authURL(); defer { cleanup(url) }
        try Data(initial.utf8).write(to: url)
        let clock = DeviceLoginClock()
        let login = XAIDeviceLogin(transport: DeviceLoginTransport([discovery, device, tokens, user]), now: { clock.now() })
        let attempt = try await login.start(authFileURL: url)
        let changed = Data(initial.replacingOccurrences(of: "old-refresh", with: "another-login-refresh").utf8)
        try changed.write(to: url); clock.advance(5)
        await #expect(throws: XAIDeviceLoginError.accountChanged) { try await login.poll(id: attempt.id) }
        #expect(try Data(contentsOf: url) == changed)
    }

    @Test func corruptSharedStoresAreNotSilentlyReplaced() async throws {
        let url = try authURL(); defer { cleanup(url) }
        let corrupt = Data("{broken".utf8); try corrupt.write(to: url)
        let transport = DeviceLoginTransport([])
        let login = XAIDeviceLogin(transport: transport)
        await #expect(throws: XAIDeviceLoginError.storage) { try await login.start(authFileURL: url) }
        #expect(try Data(contentsOf: url) == corrupt)
        #expect(await transport.recorded().isEmpty)
    }

    @Test func sharedRevisionDetectsAtomicReplacementAndLogoutWithoutCredentials() throws {
        let url = try authURL(); defer { cleanup(url) }
        let missing = XAISharedLoginRevision(url: url)
        try Data(initial.utf8).write(to: url)
        let original = XAISharedLoginRevision(url: url)
        #expect(missing != original)
        try Data(initial.replacingOccurrences(of: "old-refresh", with: "new-refresh").utf8).write(to: url, options: .atomic)
        #expect(original != XAISharedLoginRevision(url: url))
        try FileManager.default.removeItem(at: url)
        #expect(XAISharedLoginRevision(url: url) == missing)
    }
}

private actor GatedDeviceLoginTransport: AccountQuotaTransport {
    let base: DeviceLoginTransport
    let path: String
    let reply: String
    var blocked = false
    var started: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<AccountQuotaHTTPResponse, Never>?
    init(base: DeviceLoginTransport, path: String, reply: String) { self.base = base; self.path = path; self.reply = reply }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if request.url?.path != path { return try await base.data(for: request) }
        blocked = true; started?.resume(); started = nil
        return await withCheckedContinuation { release = $0 }
    }
    func waitUntilBlocked() async { if blocked { return }; await withCheckedContinuation { started = $0 } }
    func unblock() { release?.resume(returning: AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(reply.utf8))); release = nil }
}

extension XAIDeviceLoginTests {
    @Test(arguments: ["/oauth2/token", "/oauth2/userinfo"])
    func cancellationDuringAnInFlightRequestCannotSaveOrPublishALogin(_ path: String) async throws {
        let url = try authURL(); defer { cleanup(url) }
        let clock = DeviceLoginClock()
        let base = DeviceLoginTransport(path.hasSuffix("userinfo") ? [discovery, device, tokens] : [discovery, device])
        let transport = GatedDeviceLoginTransport(base: base, path: path, reply: path.hasSuffix("userinfo") ? user : tokens)
        let login = XAIDeviceLogin(transport: transport, now: { clock.now() })
        let attempt = try await login.start(authFileURL: url); clock.advance(5)
        let polling = Task { try await login.poll(id: attempt.id) }
        await transport.waitUntilBlocked()
        await login.cancel()
        await transport.unblock()
        await #expect(throws: XAIDeviceLoginError.cancelled) { try await polling.value }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
