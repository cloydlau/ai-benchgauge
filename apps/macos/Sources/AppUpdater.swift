import AppKit
import Combine
import LeaderboardCore
import Sparkle

/// Sparkle retains responsibility for signed downloads, installation and relaunch.
/// Our driver presents only a prepared update, inside the active application window.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    var activePresentationWindow: () -> NSWindow? = { nil }
    var isPresentingUpdate: Bool { driver?.isPresentingUpdate == true }
    private var updater: SPUUpdater?
    private var driver: PreparedUpdateUserDriver?
    private var observation: AnyCancellable?

    func start() {
        guard updater == nil, Bundle.main.bundleURL.pathExtension == "app",
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else { return }
        let driver = PreparedUpdateUserDriver(activeWindow: { [weak self] in
            self?.activePresentationWindow()
        })
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
            self.driver = driver
            self.updater = updater
            // Apply the policy even to installations with older saved preferences.
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
            updater.updateCheckInterval = 86400
            observation = updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
            updater.checkForUpdatesInBackground()
        } catch {
            NSLog("AI BenchGauge updater could not start: %@", error.localizedDescription)
        }
    }

    func checkForUpdates() {
        driver?.presentIfReady()
        guard canCheckForUpdates else { return }
        // Use the same silent preparation path for the version button.
        updater?.checkForUpdatesInBackground()
    }

    func presentIfReady() { driver?.presentIfReady() }
    func focusPreparedUpdateFromMenuClick() { driver?.focusFromMenuClick() }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        driver?.prepare(install: install)
        return true // Hold the cycle until the user clicks Restart to update.
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        driver?.dismissUpdateInstallation()
        NSLog("AI BenchGauge update failed: %@", error.localizedDescription)
    }
}

@MainActor
final class PreparedUpdateUserDriver: NSObject, SPUUserDriver {
    private let activeWindow: () -> NSWindow?
    private let present: (NSWindow, @escaping () -> Void) -> Void
    private var install: (() -> Void)?
    private var confirmed = false
    private var dialog: PreparedUpdatePanel?
    private(set) var isPresentingUpdate = false

    init(activeWindow: @escaping () -> NSWindow?,
         present: ((NSWindow, @escaping () -> Void) -> Void)? = nil) {
        self.activeWindow = activeWindow
        self.present = present ?? { _, _ in }
        super.init()
        if present == nil {
            usesNativeDialog = true
        }
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification,
                     NSWindow.didEndSheetNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowActivated), name: name, object: nil)
        }
    }
    @objc private func windowActivated() {
        Task { @MainActor [weak self] in self?.presentIfReady() }
    }
    private var usesNativeDialog = false

    func prepare(install: @escaping () -> Void) {
        guard self.install == nil, !isPresentingUpdate else { return }
        self.install = install
        presentIfReady()
    }

    func presentIfReady() {
        guard install != nil, !isPresentingUpdate, let window = activeWindow(),
              window.attachedSheet == nil else { return }
        isPresentingUpdate = true
        let confirm: () -> Void = { [weak self] in self?.confirmInstallation() }
        if usesNativeDialog {
            let dialog = PreparedUpdatePanel(language: AppLanguage.load(), confirm: confirm)
            self.dialog = dialog
            // Never activate the application here: the owner must already be active.
            window.beginSheet(dialog)
        } else {
            present(window, confirm)
        }
    }

    func focusFromMenuClick() {
        guard let dialog, isPresentingUpdate else { return }
        dialog.sheetParent?.orderFrontRegardless()
        dialog.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmInstallation() {
        guard isPresentingUpdate, !confirmed, let install else { return }
        confirmed = true
        self.install = nil
        install()
    }

    func show(_ request: SPUUpdatePermissionRequest,
                                    reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true,
                                        automaticUpdateDownloading: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !appcastItem.isInformationOnlyUpdate else { reply(.dismiss); return }
        if state.stage == .notDownloaded {
            reply(.install) // Download without asking; no UI until preparation finishes.
        } else {
            // Resume a download needing installation authorization, or an installer
            // left running by an earlier session. Do not initiate either in background.
            prepare { reply(.install) }
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        dismissUpdateInstallation()
        NSLog("AI BenchGauge update failed: %@", error.localizedDescription)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if confirmed { reply(.install) }
        else { prepare { reply(.install) } }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {
        install = nil
        confirmed = false
        if let dialog {
            dialog.sheetParent?.endSheet(dialog)
            dialog.orderOut(nil)
        }
        dialog = nil
        isPresentingUpdate = false
    }
    func showUpdateInFocus() { presentIfReady() }
}

/// No close button, cancellation action, Escape shortcut or Command-W dismissal.
@MainActor
final class PreparedUpdatePanel: NSPanel, NSWindowDelegate {
    init(language: AppLanguage, confirm: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 170),
                   styleMask: [.titled], backing: .buffered, defer: false)
        title = language.text("New version found", "发现新版本")
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        delegate = self
        let title = NSTextField(labelWithString: self.title)
        title.font = .boldSystemFont(ofSize: 15)
        let message = NSTextField(wrappingLabelWithString:
            language.text("The new version has downloaded. Restart to apply it.", "新版本已下载完成，重启后生效。"))
        let button = UpdateConfirmButton(title: language.text("Restart to update", "重启升级"), confirm: confirm)
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [title, message, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        if let contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ])
        }
    }
    override func cancelOperation(_ sender: Any?) {}
    override func performClose(_ sender: Any?) {}
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
}

@MainActor
private final class UpdateConfirmButton: NSButton {
    private let confirm: () -> Void
    init(title: String, confirm: @escaping () -> Void) {
        self.confirm = confirm
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(confirmUpdate)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func confirmUpdate() { isEnabled = false; confirm() }
}
