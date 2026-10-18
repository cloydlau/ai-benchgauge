import Foundation
import Testing
@testable import LeaderboardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RefreshPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed: Bool
    init(_ allowed: Bool) { self.allowed = allowed }
    func read() -> Bool { lock.withLock { allowed } }
    func set(_ value: Bool) { lock.withLock { allowed = value } }
}

private actor OwnershipTransport: AccountQuotaTransport {
    var requests: [URLRequest] = []
    let onDiscovery: @Sendable () -> Void
    init(onDiscovery: @escaping @Sendable () -> Void = {}) { self.onDiscovery = onDiscovery }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        requests.append(request)
        let body: String
        if request.url == XaiEndpointValidator.discoveryURL {
            onDiscovery()
            body = #"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#
        } else if request.url?.host == "auth.x.ai" {
            body = #"{"access_token":"fixture-access","refresh_token":"rotated","expires_in":3600}"#
        } else { body = "{}" }
        return .init(statusCode: 200, headers: [:], body: Data(body.utf8))
    }
}

struct XAIRefreshOwnershipTests {
    private let original = Data(#"{"default_account_id":"fixture","accounts":{"fixture":{"account_id":"fixture","refresh_token":"original","requires_reauth":false}}}"#.utf8)
    private var target: CCSwitchQuotaTarget {
        .init(id: "fixture", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth,
              isCurrent: true, apiKey: nil, baseURL: nil)
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("auth.json")
        try original.write(to: url)
        return url
    }

    @Test func runningSwitchDefersAllRefreshEntrypointsWithoutChangingLogin() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = OwnershipTransport()
        let client = AccountQuotaClient(transport: transport, authFileURL: url, xaiRefreshAllowed: { false })
        #expect(try await client.keepAliveXAI() == .retry)
        let previous = AccountQuotaChip(id: target.id, shortName: "xAI", websiteURL: nil,
            kind: .xaiOAuth, isCurrent: true, status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: nil)
            ]))
        let chips = try await client.refresh(targets: [target], previous: [previous])
        #expect(chips.first?.status == previous.status)
        #expect(chips.first?.isStale == true)
        #expect(try await !client.captureXAIWebsiteSubscription(Data("{}".utf8)))
        #expect(await transport.requests.isEmpty)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func stoppedSwitchResumesRenewalAfterDeferral() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let permission = RefreshPermission(false)
        let transport = OwnershipTransport()
        let client = AccountQuotaClient(transport: transport, authFileURL: url, xaiRefreshAllowed: { permission.read() })
        #expect(try await client.keepAliveXAI() == .retry)
        permission.set(true)
        #expect(try await client.keepAliveXAI() == .renewed)
        let login = try #require(XaiAuthFile.parse(Data(contentsOf: url)).flatMap(XaiAuthFile.selectedAccount))
        #expect(login.refreshToken == "rotated")
        #expect(!login.requiresReauth)
        #expect(await transport.requests.count == 2)
    }

    @Test func switchStartingDuringDiscoveryPreventsTokenExchange() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let permission = RefreshPermission(true)
        let transport = OwnershipTransport(onDiscovery: { permission.set(false) })
        let client = AccountQuotaClient(transport: transport, authFileURL: url, xaiRefreshAllowed: { permission.read() })
        #expect(try await client.keepAliveXAI() == .retry)
        #expect(await transport.requests.map(\.url) == [XaiEndpointValidator.discoveryURL])
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func loginChangingDuringDiscoveryDoesNotSendOldRefreshToken() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let replacement = Data(#"{"default_account_id":"fixture","accounts":{"fixture":{"account_id":"fixture","refresh_token":"external"}}}"#.utf8)
        let transport = OwnershipTransport(onDiscovery: { try? replacement.write(to: url, options: .atomic) })
        let client = AccountQuotaClient(transport: transport, authFileURL: url, xaiRefreshAllowed: { true })
        #expect(try await client.keepAliveXAI() == .retry)
        #expect(await transport.requests.count == 1)
        #expect(try Data(contentsOf: url) == replacement)
    }

    @Test func runningSwitchAllowsOnlyUnexpiredMatchingCachedAccessToken() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let permission = RefreshPermission(true)
        let transport = OwnershipTransport()
        let tokens = XAIAccessTokens(refreshAllowed: { permission.read() })
        let now = Date()
        _ = try await tokens.forceRefresh(transport: transport, authFileURL: url, now: now)
        let saved = try Data(contentsOf: url)
        permission.set(false)
        _ = try await tokens.billing(transport: transport, authFileURL: url, now: now.addingTimeInterval(60))
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.last?.url == XaiEndpointValidator.billingURL)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        _ = try await tokens.billing(transport: transport, authFileURL: url, now: now.addingTimeInterval(3600))
        #expect(await transport.requests.count == requests.count)
        #expect(try Data(contentsOf: url) == saved)
        // Even a still-valid access token is discarded after an external login
        // replacement, rather than being attributed to the new login.
        try original.write(to: url, options: .atomic)
        _ = try await tokens.billing(transport: transport, authFileURL: url, now: now.addingTimeInterval(60))
        #expect(await transport.requests.count == requests.count)
    }

    @Test func defaultPolicyUsesNativeProcessDetection() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let running = CCSwitchProcess.isRunning()
        let transport = OwnershipTransport()
        let client = AccountQuotaClient(transport: transport, authFileURL: url)
        #expect(try await client.keepAliveXAI() == (running ? .retry : .renewed))
        #expect(await transport.requests.count == (running ? 0 : 2))
    }
}
