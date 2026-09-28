import AppKit
import LeaderboardCore

/// Keeps the browser flow alive when the menu popover closes. Successful
/// callbacks refresh the quota immediately; closing this window cancels login.
@MainActor
final class OpenAIAccountConnection: NSObject, NSWindowDelegate {
    let source = OpenAIManagedQuotaSource()
    var onConnected: (() -> Void)?
    var onConnectingChanged: ((String?) -> Void)?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var providerID: String?
    private var authorizationURL: URL?

    func connect(_ target: CCSwitchQuotaTarget, language: AppLanguage, after previousQuotaTask: Task<Void, Never>?) {
        if task != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        providerID = target.id
        onConnectingChanged?(target.id)
        showProgress(language: language)
        task = Task { [weak self] in
            guard let self else { return }
            // A canceled quota request must finish releasing its helper before
            // the new browser flow starts using the same private profile.
            await previousQuotaTask?.value
            do {
                try Task.checkCancellation()
                let attempt = try await source.startLogin(for: target)
                authorizationURL = attempt.authorizationURL
                guard NSWorkspace.shared.open(attempt.authorizationURL) else {
                    throw OpenAIConnectionError.serviceFailed
                }
                try await source.finishLogin(attempt, for: target)
                try Task.checkCancellation()
                finish()
                onConnected?()
            } catch {
                await source.cancelLogin(for: target.id)
                let cancelled = Task.isCancelled || error is CancellationError || (error as? OpenAIConnectionError) == .cancelled
                finish()
                if !cancelled { showFailure(error, language: language) }
            }
        }
    }

    private func showProgress(language: AppLanguage) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = language.text("Connect OpenAI", "连接 OpenAI")
        window.isReleasedWhenClosed = false
        window.delegate = self
        let label = NSTextField(wrappingLabelWithString: language.text(
            "Complete the OpenAI sign-in in your browser. Your quota will refresh automatically when authorization finishes.",
            "请在浏览器中完成 OpenAI 登录。授权成功后，余量会自动刷新。"
        ))
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let reopen = NSButton(title: language.text("Reopen authorization page", "重新打开授权页"), target: self, action: #selector(reopenBrowser))
        let cancel = NSButton(title: language.text("Cancel", "取消"), target: self, action: #selector(cancelClicked))
        let buttons = NSStackView(views: [reopen, cancel])
        buttons.spacing = 12
        let stack = NSStackView(views: [spinner, label, buttons])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc private func reopenBrowser() {
        if let authorizationURL { NSWorkspace.shared.open(authorizationURL) }
    }

    @objc private func cancelClicked() { cancel() }
    func windowWillClose(_ notification: Notification) { cancel() }

    func cancel() {
        guard let task else { return }
        task.cancel()
        if let providerID {
            Task { await source.cancelLogin(for: providerID) }
        }
        // Keep the task reserved until cancellation has released the service.
        window?.delegate = nil
        window?.close()
        window = nil
    }

    private func finish() {
        window?.delegate = nil
        window?.close()
        window = nil
        task = nil
        providerID = nil
        authorizationURL = nil
        onConnectingChanged?(nil)
    }

    private func showFailure(_ error: Error, language: AppLanguage) {
        let alert = NSAlert()
        alert.messageText = language.text("OpenAI authorization did not finish", "OpenAI 授权未完成")
        switch error as? OpenAIConnectionError {
        case .helperMissing:
            alert.informativeText = language.text(
                "Direct authorization uses the official Codex service. Install Codex CLI or the ChatGPT/Codex desktop app, then click the quota card to retry.",
                "直接授权需要官方 Codex 服务。请安装 Codex CLI 或 ChatGPT/Codex 桌面应用，然后点击余量卡片重试。"
            )
        case .accountMismatch:
            alert.informativeText = language.text(
                "The browser signed in to a different account from this CC Switch provider. Click the quota card again and sign in with the original OpenAI account.",
                "浏览器登录的账号与此 CC Switch 供应商不一致。请再次点击余量卡片，使用原来的 OpenAI 账号授权。"
            )
        case .timedOut:
            alert.informativeText = language.text("Authorization timed out. Click the quota card to try again.", "授权已超时，请点击余量卡片重新授权。")
        default:
            alert.informativeText = language.text(
                "The authorization service could not complete sign-in. Check your network and try again. If another login is using the local callback port, finish or cancel it first.",
                "授权服务未能完成登录，请检查网络后重试。如果另一个登录流程占用了本机回调端口，请先完成或取消该登录。"
            )
        }
        alert.addButton(withTitle: language.text("OK", "好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
