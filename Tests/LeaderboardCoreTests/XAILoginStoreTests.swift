import Foundation
import Testing
@testable import LeaderboardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor IndependentXAITransport: AccountQuotaTransport {
    private(set) var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        requests.append(request)
        try await Task.sleep(for: .milliseconds(10))
        let body = request.url == XaiEndpointValidator.discoveryURL
            ? #"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#
            : #"{"access_token":"app-access","refresh_token":"app-rotated","expires_in":3600}"#
        return .init(statusCode: 200, headers: [:], body: Data(body.utf8))
    }
}

struct XAILoginStoreTests {
    private func login(_ id: String, token: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["default_account_id": id,
            "accounts": [id: ["account_id": id, "refresh_token": token]]])
    }

    @Test func selectedAccountsHaveSeparateStablePathsWithoutCopyingSharedCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appending(path: "cc-switch.json"), owned = root.appending(path: "owned")
        let noSelection = XAILoginStore.authURL(sharedAuthURL: shared, directory: owned)
        try login("account-a", token: "cc-token").write(to: shared)
        let first = XAILoginStore.authURL(sharedAuthURL: shared, directory: owned)
        #expect(first != shared && first != noSelection)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!first.lastPathComponent.contains("account-a"))
        try login("account-a", token: "cc-rotated").write(to: shared)
        #expect(XAILoginStore.authURL(sharedAuthURL: shared, directory: owned) == first)
        try login("account-b", token: "cc-other").write(to: shared)
        let second = XAILoginStore.authURL(sharedAuthURL: shared, directory: owned)
        #expect(second != first && second != noSelection)
        try login("account-a", token: "cc-new").write(to: shared)
        #expect(XAILoginStore.authURL(sharedAuthURL: shared, directory: owned) == first)
        #expect(XAILoginStore.isAppManaged(first, directory: owned))
        #expect(!XAILoginStore.isAppManaged(shared, directory: owned))
        #expect(!XAILoginStore.isAppManaged(owned.appending(path: "../outside.json"), directory: owned))
    }

    @Test func runningSwitchAllowsAppRenewalWithoutRotatingItsSharedToken() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let owned = root.appending(path: "owned")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appending(path: "cc-switch.json")
        let original = try login("account-a", token: "cc-token")
        try original.write(to: shared)
        let app = XAILoginStore.authURL(sharedAuthURL: shared, directory: owned)
        try login("account-a", token: "app-token").write(to: app)
        let transport = IndependentXAITransport()
        let tokens = XAIAccessTokens(managedAuthDirectory: owned, ccSwitchRunning: { true })
        async let first = tokens.forceRefresh(transport: transport, authFileURL: app, now: Date())
        async let second = tokens.forceRefresh(transport: transport, authFileURL: app, now: Date())
        for result in try await [first, second] {
            guard case .token("app-access") = result else { Issue.record("App renewal was blocked"); return }
        }
        #expect(await transport.requests.count == 2)
        let request = try #require(await transport.requests.last)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("refresh_token=app-token"))
        #expect(XaiAuthFile.parse(try Data(contentsOf: app)).flatMap(XaiAuthFile.selectedAccount)?.refreshToken == "app-rotated")
        #expect(try Data(contentsOf: shared) == original)
        guard case .token("app-access") = try await tokens.forceRefresh(transport: transport, authFileURL: app,
                                                                        now: Date().addingTimeInterval(6 * 3600)) else {
            Issue.record("Later renewal was blocked while CC Switch remained open"); return
        }
        let renewed = try #require(await transport.requests.last)
        #expect(String(decoding: renewed.httpBody ?? Data(), as: UTF8.self).contains("refresh_token=app-rotated"))
        #expect(await transport.requests.count == 3)
        // Even the same actor must retain the protection for a shared file.
        guard case .failure(.refreshDeferred) = try await tokens.forceRefresh(transport: transport, authFileURL: shared, now: Date()) else {
            Issue.record("Shared credentials were allowed to rotate"); return
        }
        #expect(await transport.requests.count == 3)
        #expect(try Data(contentsOf: shared) == original)
    }
}
