import AppKit
import WebKit
import LeaderboardCore

/// A dedicated official-site session. No Chrome cookies, credential export,
/// DOM date guesses or handwritten deadlines. The core checks the response's
/// xaiUserId against the selected OAuth account before accepting its date.
@MainActor
final class XAIWebsiteSubscriptionSource: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private let webView: WKWebView
    private let defaults: UserDefaults
    private let status = NSTextField(wrappingLabelWithString: "")
    private var window: NSWindow?
    private var pollTask: Task<Void, Never>?
    private var lastAttempt: Date?
    private var presenting = false
    var onData: ((Data) async -> Bool)?
    var onUpdated: (() -> Void)?

    init(defaults: UserDefaults = .standard, usesVisualFixture: Bool = false) {
        self.defaults = defaults
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = usesVisualFixture ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: UUID(uuidString: "6749434C-241D-440E-9BE9-F40377147B64")!)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func connect(language: AppLanguage) {
        presenting = true
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.contentView = makeContent(language: language)
            newWindow.center()
            window = newWindow
        }
        window?.title = language.text("Connect xAI plan", "连接 xAI 套餐")
        setStatus(language.text("Sign in to the same xAI account used for your quota. The app will read the plan date automatically.",
            "请登录与额度相同的 xAI 账号，应用会自动读取套餐日期。"))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastAttempt = Date()
        webView.load(URLRequest(url: URL(string: "https://grok.com/")!))
        startPolling(attempts: 90)
    }

    func refreshIfConnected() {
        guard defaults.bool(forKey: "xaiSubscriptionWebsiteConnected"), !presenting,
              lastAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAttempt = Date()
        webView.load(URLRequest(url: URL(string: "https://grok.com/")!))
        startPolling(attempts: 6)
    }

    func cancel() {
        pollTask?.cancel(); pollTask = nil
        webView.stopLoading()
    }

    func windowWillClose(_ notification: Notification) {
        presenting = false
        cancel()
    }

    func makeContent(language: AppLanguage, fixture: Bool = false, fixtureState: String = "") -> NSView {
        let container = XAIConnectionContent(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let title = NSTextField(labelWithString: language.text("Connect xAI plan", "连接 xAI 套餐"))
        title.font = .boldSystemFont(ofSize: 17)
        let help = NSTextField(wrappingLabelWithString: language.text(
            "Use the same xAI account as CC Switch. After sign-in or verification, the app queries the official subscription and refreshes its date automatically. Usage stays available while connecting.",
            "请使用与 CC Switch 相同的 xAI 账号。登录或验证完成后，应用自动查询官方订阅并刷新日期；连接期间仍可查看余量。"))
        help.font = .systemFont(ofSize: 13)
        help.textColor = .secondaryLabelColor
        let retry = NSButton(title: language.text("Query again", "重新查询"), target: self, action: #selector(queryAgain))
        retry.bezelStyle = .rounded
        retry.setContentHuggingPriority(.required, for: .horizontal)
        retry.setContentCompressionResistancePriority(.required, for: .horizontal)
        let browserArea: NSView
        if fixture {
            let placeholder = NSView()
            placeholder.wantsLayer = true
            placeholder.layer?.backgroundColor = NSColor.white.cgColor
            browserArea = placeholder
        } else { browserArea = webView }
        let header = NSStackView(views: [title, help])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 8
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.stringValue = stateText(fixtureState, language: language)
        for view in [header, retry, status, browserArea] { view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            retry.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            retry.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: retry.leadingAnchor, constant: -12),
            status.centerYAnchor.constraint(equalTo: retry.centerYAnchor),
            browserArea.topAnchor.constraint(equalTo: retry.bottomAnchor, constant: 12),
            browserArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            browserArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            browserArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    @objc private func queryAgain() { startPolling(attempts: 90) }
    private func setStatus(_ text: String) { status.stringValue = text }

    private func startPolling(attempts: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<attempts {
                guard !Task.isCancelled else { return }
                if await capture() {
                    defaults.set(true, forKey: "xaiSubscriptionWebsiteConnected")
                    presenting = false
                    window?.orderOut(nil)
                    onUpdated?()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
                if presenting && window?.isVisible != true { presenting = false; return }
            }
            if !Task.isCancelled && presenting { setStatus(stateText("paused", language: .load())) }
        }
    }

    private func stateText(_ state: String, language: AppLanguage) -> String {
        switch state {
        case "verification": return language.text("Complete the official site's verification below; the app retries automatically.", "请在下方官网完成验证，应用会自动重试。")
        case "mismatch": return language.text("No matching active plan date found. Check that this is the quota account.", "未找到同一额度账号的有效套餐日期，请检查网页登录账号。")
        case "paused": return language.text("Query paused. After sign-in or verification, select Query again.", "查询已暂停。完成登录或验证后，请点击重新查询。")
        default: return language.text("Waiting for official sign-in or verification…", "等待官网登录或验证…")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if presenting && window?.isVisible == true { startPolling(attempts: 90) }
    }

    private func capture() async -> Bool {
        guard webView.url?.scheme == "https", webView.url?.host == "grok.com", !webView.isLoading else { return false }
        let script = """
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 8000);
        try {
          const response = await fetch('/rest/subscriptions', {credentials: 'include', headers: {Accept: 'application/json'}, signal: controller.signal});
          const body = await response.text();
          return {status: response.status, body: body.length <= 1048576 ? body : ''};
        } catch (_) { return {status: 0, body: ''}; }
        finally { clearTimeout(timer); }
        """
        guard let result = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any],
              let code = result["status"] as? Int else { return false }
        guard !Task.isCancelled, webView.url?.scheme == "https", webView.url?.host == "grok.com" else { return false }
        let language = AppLanguage.load()
        if code == 403 {
            setStatus(stateText("verification", language: language))
            return false
        }
        guard (200...299).contains(code), let body = result["body"] as? String, body.utf8.count <= 1_048_576 else { return false }
        guard await onData?(Data(body.utf8)) == true else {
            setStatus(stateText("mismatch", language: language))
            return false
        }
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == "https" ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }
}

private final class XAIConnectionContent: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
