import AppKit
import Combine
import Foundation
import LeaderboardCore
import Testing
import WebKit
@testable import leaderboard_menu

@MainActor
private final class QwenFixtureWebView: WKWebView {
    var pageText = "您当前还未登录，登录后可使用完整服务"
    var requests = 0
    var finishNavigation = true
    override var url: URL? { URL(string: "https://platform.qianwenai.com/home/analytics/token-plan/individual") }
    override func load(_ request: URLRequest) -> WKNavigation? {
        requests += 1
        if finishNavigation {
            Task { @MainActor [weak self] in
                guard let self else { return }
                navigationDelegate?.webView?(self, didFinish: nil)
            }
        }
        return nil
    }
    override func evaluateJavaScript(_ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil) {
        completionHandler?(pageText, nil)
    }
}

private actor QwenHeldSource: QwenQuotaSource {
    private var continuation: CheckedContinuation<Data?, Never>?
    var started = false
    func loadSummary() async -> Data? {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: Data("您当前还未登录，登录后可使用完整服务".utf8))
        continuation = nil
    }
}

@Suite(.serialized) @MainActor
struct QwenWebsiteQuotaSourceTests {
    private let quotaText = "月额度\n剩余量 75 %"

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Qwen login verification did not settle")
    }

    @Test(arguments: [false, true])
    func closingLoginRechecksTheSiteAndReplacesExpiredState(wasConnected: Bool) async throws {
        _ = NSApplication.shared
        let suite = "qwen-login.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(wasConnected, forKey: "qwenWebsiteConnected")
        let browser = QwenFixtureWebView()
        let source = QwenWebsiteQuotaSource(defaults: defaults, webView: browser)
        var updates: [AccountQuotaChip.Status] = []
        source.onUpdated = { updates.append($0) }
        source.connect()
        try await waitFor { updates.last == .message(AccountQuotaMessage.reauthRequired) }
        _ = await source.loadSummary()
        #expect(browser.requests == 1) // A scheduled refresh cannot redirect login.
        browser.pageText = quotaText
        try #require(browser.window).close()
        #expect(updates.last == .pending)
        try await waitFor { if case .qwenWebsite = updates.last { return true }; return false }
        #expect(browser.requests == 2)
        #expect(defaults.bool(forKey: "qwenWebsiteConnected"))
        #expect(source.cachedQuota()?.remainingPercent == 75)
        #expect(updates.last == .qwenWebsite(.init(periodLabel: "1mo", remainingPercent: 75, resetsAt: nil)))
    }

    @Test(arguments: ["您当前还未登录，登录后可使用完整服务", "暂无个人版套餐"])
    func closingWithoutUsableQuotaReportsTheActualSiteState(text: String) async throws {
        _ = NSApplication.shared
        let suite = "qwen-login-failure.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = QwenFixtureWebView()
        let source = QwenWebsiteQuotaSource(defaults: defaults, webView: browser)
        var updates: [AccountQuotaChip.Status] = []
        source.onUpdated = { updates.append($0) }
        source.connect()
        try await waitFor { !updates.isEmpty }
        browser.pageText = text
        try #require(browser.window).close()
        try await waitFor { updates.last != .pending }
        #expect(updates.last == QwenWebsiteQuotaParser.failureStatus(in: Data(text.utf8)))
        #expect(source.cachedQuota() == nil)
        #expect(defaults.bool(forKey: "qwenWebsiteConnected") == (text == "暂无个人版套餐"))
    }

    @Test func automaticallyClosingAfterCaptureDoesNotStartAnotherRead() async throws {
        _ = NSApplication.shared
        let suite = "qwen-login-auto.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = QwenFixtureWebView()
        browser.pageText = quotaText
        let source = QwenWebsiteQuotaSource(defaults: defaults, webView: browser)
        var updates: [AccountQuotaChip.Status] = []
        source.onUpdated = { updates.append($0) }
        source.connect()
        try await waitFor { !updates.isEmpty }
        #expect(browser.requests == 1)
        #expect(updates.count == 1)
        #expect(browser.window?.isVisible != true)
    }

    @Test func reopeningLoginCancelsThePreviousCloseVerification() async throws {
        _ = NSApplication.shared
        let suite = "qwen-login-reopen.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = QwenFixtureWebView()
        let source = QwenWebsiteQuotaSource(defaults: defaults, webView: browser)
        var updates: [AccountQuotaChip.Status] = []
        source.onUpdated = { updates.append($0) }
        source.connect()
        try await waitFor { !updates.isEmpty }
        browser.finishNavigation = false
        try #require(browser.window).close()
        try await waitFor { browser.requests == 2 }
        browser.finishNavigation = true
        browser.pageText = quotaText
        source.connect()
        try await waitFor { if case .qwenWebsite = updates.last { return true }; return false }
        #expect(browser.requests == 3)
        #expect(!updates.contains(.message(AccountQuotaMessage.queryFailed)))
    }

    @Test func aPostLoginPageThatNeverFinishesCannotLeaveTheCardPending() async throws {
        _ = NSApplication.shared
        let suite = "qwen-login-timeout.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = QwenFixtureWebView()
        let source = QwenWebsiteQuotaSource(defaults: defaults, webView: browser,
            requestTimeout: .milliseconds(30))
        var updates: [AccountQuotaChip.Status] = []
        source.onUpdated = { updates.append($0) }
        source.connect()
        try await waitFor { !updates.isEmpty }
        browser.finishNavigation = false
        try #require(browser.window).close()
        try await waitFor { updates.last != .pending }
        #expect(updates.last == .message(AccountQuotaMessage.queryFailed))
        #expect(!defaults.bool(forKey: "qwenWebsiteConnected"))
    }

    @Test(arguments: [false, true])
    func anOlderRefreshCannotOverwriteLoginVerification(completed: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "qwen-state.\(UUID())")
        let suite = "qwen-state.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let target = CCSwitchQuotaTarget(id: "qwen", shortName: "Qwen", websiteURL: nil,
            kind: .qwen, isCurrent: true, apiKey: nil, baseURL: nil)
        let held = QwenHeldSource()
        let client = AccountQuotaClient(qwenQuotaSource: held)
        let loaded = CCSwitchQuotaLoad(result: .records([]), isInstalled: true, currentProviderID: "qwen",
            xaiAuthURL: root.appending(path: "auth.json"), officialTargets: [], ccSwitchTargets: [target],
            shouldAskClaudeKeychainConsent: false)
        let state = AppState(cache: LeaderboardCache(fileURL: root.appending(path: "cache.json")),
            defaults: defaults, configuration: .init(previewCCSwitchState: .configured),
            quotaClient: client, quotaProviderLoad: { loaded })
        defer { state.beginQuitting() }
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await held.started }
        let newStatus: AccountQuotaChip.Status = completed
            ? .qwenWebsite(.init(periodLabel: "1mo", remainingPercent: 75, resetsAt: nil)) : .pending
        state.applyQwenWebsiteStatus(newStatus)
        var assignments = 0
        let observer = state.$quotaChips.sink { _ in assignments += 1 }
        defer { observer.cancel() }
        let beforeRelease = assignments
        await held.release()
        try await waitFor { assignments > beforeRelease }
        #expect(state.quotaChips.first { $0.kind == .qwen }?.status == newStatus)
    }
}
