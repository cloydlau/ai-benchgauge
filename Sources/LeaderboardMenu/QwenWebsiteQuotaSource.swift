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

    private let webView: WKWebView
    private var loginWindow: NSWindow?
    private var pending: CheckedContinuation<Data?, Never>?
    private var pollTask: Task<Void, Never>?
    private var connected: Bool
    var onConnected: (() -> Void)?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        connected = UserDefaults.standard.bool(forKey: Self.connectedKey)
        super.init()
        webView.navigationDelegate = self
    }

    func connect() {
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
        webView.load(URLRequest(url: Self.usageURL))
    }

    func loadSummary() async -> Data? {
        guard connected else { return nil }
        finish(nil)
        return await withCheckedContinuation { continuation in
            pending = continuation
            webView.load(URLRequest(url: Self.usageURL))
            startPolling()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPolling()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if let text = try? await webView.evaluateJavaScript("document.body.innerText") as? String {
                    let data = Data(text.utf8)
                    if QwenWebsiteQuotaParser.parse(data) != nil {
                        let wasConnected = connected
                        connected = true
                        UserDefaults.standard.set(true, forKey: Self.connectedKey)
                        finish(data)
                        if !wasConnected {
                            loginWindow?.close()
                            onConnected?()
                        }
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            finish(nil)
        }
    }

    private func finish(_ data: Data?) {
        pending?.resume(returning: data)
        pending = nil
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
