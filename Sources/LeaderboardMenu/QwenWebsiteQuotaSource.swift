import AppKit
import Foundation
import WebKit
import LeaderboardCore

/// Reads only the quota text the official page renders after the user signs in
/// inside this app. WebKit owns its own cookies; CLI credentials are untouched.
@MainActor
final class QwenWebsiteQuotaSource: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private static let usageURL = URL(
        string: "https://platform.qianwenai.com/home/analytics/token-plan/individual"
    )!
    private static let connectedKey = "qwenWebsiteConnected"
    private static let cachedQuotaKey = "qwenWebsiteCachedQuota"
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60

    private let webView: WKWebView
    private var loginWindow: NSWindow?
    private var activeNavigation: WKNavigation?
    private var pending: CheckedContinuation<Data?, Never>?
    private var pollTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var connected: Bool
    private var presentingLogin = false
    var onConnected: (() -> Void)?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Some of the quota page is rendered lazily from the viewport. Keep a
        // real viewport even when the web view is not currently visible.
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1080, height: 740),
            configuration: configuration
        )
        connected = UserDefaults.standard.bool(forKey: Self.connectedKey)
        super.init()
        webView.navigationDelegate = self
    }

    func connect() {
        presentingLogin = true
        if loginWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "连接千问官网用量"
            window.contentView = webView
            window.center()
            loginWindow = window
        }
        loginWindow?.makeKeyAndOrderFront(nil)
        loginWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        activeNavigation = webView.load(URLRequest(url: Self.usageURL))
    }

    func loadSummary() async -> Data? {
        guard connected else { return nil }
        pollTask?.cancel()
        timeoutTask?.cancel()
        finish(nil)
        return await withCheckedContinuation { continuation in
            pending = continuation
            activeNavigation = webView.load(URLRequest(url: Self.usageURL))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, let self else { return }
                finish(cachedSummary())
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        startPolling()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        finish(cachedSummary())
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        finish(cachedSummary())
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if let text = try? await webView.evaluateJavaScript("document.body.innerText") as? String {
                    let data = Data(text.utf8)
                    if let quota = QwenWebsiteQuotaParser.parse(data) {
                        let shouldNotify = presentingLogin || !connected
                        connected = true
                        UserDefaults.standard.set(true, forKey: Self.connectedKey)
                        if let persisted = QwenWebsiteQuotaParser.persistedData(for: quota) {
                            UserDefaults.standard.set(persisted, forKey: Self.cachedQuotaKey)
                        }
                        finish(data)
                        if presentingLogin {
                            presentingLogin = false
                            loginWindow?.close()
                        }
                        if shouldNotify {
                            onConnected?()
                        }
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            finish(cachedSummary())
        }
    }

    private func finish(_ data: Data?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(returning: data)
        pending = nil
    }

    func cachedQuota(now: Date = Date()) -> QwenWebsiteQuota? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.cachedQuotaKey),
              let quota = QwenWebsiteQuotaParser.parse(data),
              quota.isCached,
              let capturedAt = quota.capturedAt,
              (0...Self.cacheLifetime).contains(now.timeIntervalSince(capturedAt)),
              quota.resetsAt.map({ $0 > now }) ?? true else {
            defaults.removeObject(forKey: Self.cachedQuotaKey)
            return nil
        }
        return quota
    }

    private func cachedSummary(now: Date = Date()) -> Data? {
        guard cachedQuota(now: now) != nil else { return nil }
        return UserDefaults.standard.data(forKey: Self.cachedQuotaKey)
    }
}

struct QwenPreferredQuotaSource: QwenQuotaSource {
    let website: QwenWebsiteQuotaSource
    private let cli = QwenCLIQuotaSource()

    func loadSummary() async -> Data? {
        if let websiteSummary = await website.loadSummary() {
            return websiteSummary
        }
        return await cli.loadSummary()
    }
}
