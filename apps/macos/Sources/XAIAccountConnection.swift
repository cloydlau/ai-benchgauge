import AppKit
import LeaderboardCore

/// An app-owned session keeps quota refresh independent of CC Switch.
@MainActor
final class XAIAccountConnection: NSObject, NSWindowDelegate {
    private let source = XAIDeviceLogin()
    var onConnected: (() -> Void)?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var authorizationURL: URL?
    private var language: AppLanguage = .english
    private let status = NSTextField(wrappingLabelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private lazy var retry = NSButton(title: "", target: self, action: #selector(retryClicked))
    private lazy var copy = NSButton(title: "", target: self, action: #selector(copyClicked))
    private lazy var close = NSButton(title: "", target: self, action: #selector(closeClicked))
    private let spinner = NSProgressIndicator()

    func connect(language: AppLanguage) {
        self.language = language
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = language.text("Sign in to xAI", "登录 xAI")
        window.delegate = self
        window.contentView = makeContent(language: language)
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        begin()
    }

    func makeContent(language: AppLanguage, fixtureState: String = "starting") -> NSView {
        self.language = language
        let content = XAIDeviceLoginContent(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        let title = NSTextField(labelWithString: language.text("Sign in to xAI", "登录 xAI"))
        title.font = .boldSystemFont(ofSize: 17)
        let help = NSTextField(wrappingLabelWithString: language.text(
            "Sign in once with your CC Switch xAI account. BenchGauge refreshes independently; CC Switch can stay open.",
            "使用与 CC Switch 相同的 xAI 账号授权一次，AI 天梯即可独立更新余量，无需退出 CC Switch。"))
        help.font = .systemFont(ofSize: 13); help.textColor = .secondaryLabelColor
        code.font = .monospacedSystemFont(ofSize: 23, weight: .semibold)
        code.isSelectable = true
        code.stringValue = fixtureState == "waiting" ? "Q2QH-TEST" : ""
        status.font = .systemFont(ofSize: 13)
        spinner.style = .spinning; spinner.controlSize = .small
        for button in [retry, copy, close] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [retry, copy, close]); buttons.spacing = 10
        let row = NSStackView(views: [spinner, status]); row.alignment = .centerY; row.spacing = 10
        let stack = NSStackView(views: [title, help, code, row, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        showState(fixtureState)
        return content
    }

    private func showState(_ state: String) {
        status.stringValue = XAIDeviceLoginText.status(state, language: language)
        let waiting = state == "waiting", starting = state == "starting", saved = state == "saved"
        retry.title = waiting ? language.text("Open authorization page", "打开授权页") : language.text("Try again", "重试")
        retry.isEnabled = !starting && !saved
        retry.isHidden = saved
        copy.title = language.text("Copy code", "复制授权码"); copy.isHidden = !waiting
        code.isHidden = !waiting
        close.title = saved ? language.text("Done", "完成") : language.text("Cancel", "取消")
        spinner.isHidden = !waiting && !starting
        if waiting || starting { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func begin() {
        guard task == nil else { return }
        authorizationURL = nil; code.stringValue = ""; showState("starting")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let attempt = try await source.startForBenchGauge()
                try Task.checkCancellation()
                authorizationURL = attempt.authorizationURL; code.stringValue = attempt.userCode
                showState("waiting")
                guard NSWorkspace.shared.open(attempt.authorizationURL) else { throw XAIDeviceLoginError.network }
                var interval = attempt.interval
                while true {
                    try await Task.sleep(for: .seconds(interval))
                    switch try await source.poll(id: attempt.id) {
                    case .waiting(let next): interval = next
                    case .connected:
                        try Task.checkCancellation()
                        // Dismiss before starting the independent quota query.
                        // Clear the completed login task so closing cannot cancel it.
                        task = nil
                        cancel()
                        onConnected?()
                        return
                    }
                }
            } catch {
                await source.cancel()
                let cancelled = error is CancellationError || Task.isCancelled || error as? XAIDeviceLoginError == .cancelled
                task = nil; authorizationURL = nil
                if !cancelled { showState((error as? XAIDeviceLoginError)?.state ?? "failed") }
                else if window != nil { begin() }
            }
        }
    }

    @objc private func retryClicked() {
        if let authorizationURL { NSWorkspace.shared.open(authorizationURL) }
        else { begin() }
    }
    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.stringValue, forType: .string)
    }
    @objc private func closeClicked() { cancel() }
    func windowWillClose(_ notification: Notification) { cancel() }
    func cancel() {
        task?.cancel()
        window?.delegate = nil; window?.close(); window = nil
        authorizationURL = nil
    }
}

private final class XAIDeviceLoginContent: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
