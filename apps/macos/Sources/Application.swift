import AppKit
import Combine
import SwiftUI
import LeaderboardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stateController: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--visual-test") {
            Task { @MainActor in
                do { try await NativeVisualCapture.run(); NSApp.terminate(nil) }
                catch {
                    FileHandle.standardError.write(Data("Native visual capture failed: \(error)\n".utf8))
                    exit(1)
                }
            }
            return
        }
        #endif
        BundleIdentifierMigration.run()
        let cache: LeaderboardCache
        do {
            cache = LeaderboardCache(fileURL: try LeaderboardCache.defaultFileURL())
        } catch {
            cache = LeaderboardCache(fileURL: temporaryCacheURL())
        }
        let state = AppState(cache: cache)
        stateController = StatusBarController(state: state)
        state.start()
        if CommandLine.arguments.contains("--connect-xai-subscription") {
            state.connectXAISubscription()
        }
        AppUpdater.shared.start()
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ai-benchgauge.json", directoryHint: .inferFromPath)
    }
}

@MainActor
enum ClaudeKeychainConsentAlert {
    static func make(language: AppLanguage) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = language.text(
            "Show Claude usage?",
            "查询 Claude 余量？"
        )
        alert.informativeText = language.text(
            "BenchGauge reads the Claude Code Keychain token to query official Claude usage. It does not read or save the refresh token. macOS may ask again for system permission; skipping affects only this query.",
            "为了让 Claude 余量自动显示，BenchGauge 会读取 Claude Code 的钥匙串访问令牌，仅用于 Anthropic 官方余量接口，也不会读取或保存刷新令牌。macOS 可能再显示系统授权；暂不开启只影响这项查询。"
        )
        alert.addButton(withTitle: language.text("Allow and continue", "允许并继续"))
        alert.addButton(withTitle: language.text("Not now", "暂不"))
        return alert
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    @IBOutlet private var button: NSStatusBarButton?
    private static let statusItemSymbolName = "brain.head.profile"
    private let popover = NSPopover()
    private let state: AppState
    private let statusItem: NSStatusItem
    private let hosting: NSHostingController<LeaderboardView>
    private var stateObservation: AnyCancellable?
    private var presentedMode: PanelMode
    private var leaderboardWindow: NSWindow?
    private var lastLeaderboardWindowFrame: NSRect?
    private var outsideClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    /// Real clicks stay transparent until the post-show frame pin lands.
    /// Pre-warm shows the popover invisibly and must not surface that window.
    private var revealAfterSettle = false
    /// Frame captured after AppKit anchors the popover, plus the screen-edge
    /// inset. Later level resets must not replace this with a shifted frame.
    private var settledPopoverFrame: NSRect?
    private var isApplyingSettledFrame = false
    private var framePinInstalled = false
    private var framePinAttempts = 0
    private var framePinGeneration = 0
    private var isPresentingClaudeKeychainConsent = false

    private var maximumWidth: CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        return max(600, floor((screen?.visibleFrame.width ?? 1136) - 16))
    }

    init(state: AppState) {
        self.state = state
        presentedMode = state.panelMode
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let initialMaximumWidth = max(600, floor((NSScreen.main?.visibleFrame.width ?? 1136) - 16))
        hosting = NSHostingController(rootView: LeaderboardView(state: state, maximumWidth: initialMaximumWidth))
        super.init()

        // .applicationDefined instead of .transient: a transient popover closes
        // as soon as a drop-down Menu opens its own window outside the popover,
        // which swallows the menu item action that opens the purchase link.
        popover.behavior = .applicationDefined
        // A size or origin change while animates is true replays the anchor
        // slide. That second slide is the down-left twitch after open.
        popover.animates = false
        popover.delegate = self
        let contentSize = LeaderboardView.preferredSize(for: state, maximumWidth: initialMaximumWidth)
        // Resize explicitly so AppKit cannot re-anchor the popover on each
        // SwiftUI layout pass.
        hosting.sizingOptions = []
        hosting.preferredContentSize = contentSize
        popover.contentViewController = hosting
        popover.contentSize = contentSize

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateStatusItem()

        stateObservation = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.updatePresentationMode()
                self?.updatePanelWidth()
                self?.updateDismissMonitor()
                self?.presentClaudeKeychainConsentIfNeeded()
            }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard application.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
                self?.closeIfUnfocused()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowSheetDidEnd(_:)),
            name: NSWindow.didEndSheetNotification,
            object: nil
        )
        AppUpdater.shared.activePresentationWindow = { [weak self] in
            guard let self, NSApp.isActive else { return nil }
            if self.state.panelMode == .window {
                guard let window = self.leaderboardWindow, window.isVisible,
                      !window.isMiniaturized, window.isKeyWindow else { return nil }
                return window
            }
            guard self.popover.isShown, let window = self.hosting.view.window,
                  window.isVisible, window.alphaValue > 0, window.isKeyWindow else { return nil }
            return window
        }

        // Pre-warm: create the popover window and run the first SwiftUI
        // layout pass at launch (invisibly), so the first click opens
        // instantly instead of paying that cost on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.prewarmPopover()
        }
    }

    private func prewarmPopover() {
        guard state.panelMode != .window, !popover.isShown, let button = statusItem.button else { return }
        updatePanelWidth()
        revealAfterSettle = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.revealAfterSettle else { return }
            self.popover.performClose(nil)
            self.popover.contentViewController?.view.window?.alphaValue = 1
        }
    }

    #if DEBUG
    /// Capture the production status button using public fixture data only.
    func visualStatusButton(width: CGFloat) -> NSStatusBarButton? {
        statusItem.length = width
        updateStatusItem()
        return statusItem.button
    }

    func finishVisualStatusCapture() {
        NSStatusBar.system.removeStatusItem(statusItem)
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
    #endif

    /// Reads the projection instead of re-deriving one, so the item can never
    /// hold an amount older than the chip the panel is showing.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard let quota = state.menuBarQuota else {
            button.toolTip = "AI BenchGauge"
            setStatusItemLabel(button, label: nil)
            return
        }
        let quotaText = state.selectedLanguage.quotaText(quota.quota)
        setStatusItemLabel(button, label: "\(quota.name) · \(quotaText)")
        button.toolTip = "AI BenchGauge · \(quota.fullName) · \(quotaText)"
    }

    /// AppKit centers `button.image` in the status item but lays the title out on
    /// its own, so an image beside a title does not share the text's baseline and
    /// reads as vertically off. Drawing the symbol as a text attachment keeps it
    /// on the label's baseline. The icon-only state keeps the native image, which
    /// AppKit already centers in the item.
    private func setStatusItemLabel(_ button: NSStatusBarButton, label: String?) {
        guard let label, !label.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = statusItemSymbol(for: button)
            return
        }
        let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
        guard let symbol = statusItemSymbol(for: button) else {
            button.image = nil
            button.title = label
            return
        }
        let attachment = NSTextAttachment()
        attachment.image = symbol
        // A symbol's alignment rect bottom is its baseline, so this drops the
        // icon onto the label's baseline instead of floating above or below it.
        attachment.bounds = CGRect(
            x: 0,
            y: -symbol.alignmentRect.minY,
            width: symbol.size.width,
            height: symbol.size.height
        )
        let title = NSMutableAttributedString(attachment: attachment)
        title.append(NSAttributedString(string: " \(label)", attributes: [.font: font]))
        button.image = nil
        button.attributedTitle = title
    }

    private func statusItemSymbol(for button: NSStatusBarButton) -> NSImage? {
        let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
        let symbol = NSImage(
            systemSymbolName: Self.statusItemSymbolName,
            accessibilityDescription: "AI BenchGauge"
        )
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        return symbol?.withSymbolConfiguration(configuration) ?? symbol
    }

    /// A status-item popover is a child of the menu-bar window, so it inherits
    /// status-bar level. Detach that relationship after show, keeping that
    /// level only for Always on top. Other modes use the normal window level
    /// so later clicks on other windows can cover them.
    ///
    /// Detaching and the level change make AppKit re-anchor the panel. On a
    /// right-side status item that re-anchor shifts the window down and left.
    /// Pin the frame from the first show instead of adopting the shifted one.
    private func settlePopoverWindow() {
        guard popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        if settledPopoverFrame == nil {
            settledPopoverFrame = frameInsetFromScreenEdges(
                window.frame,
                screen: window.screen ?? NSScreen.main
            )
        }
        window.parent?.removeChildWindow(window)
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = false
            panel.hidesOnDeactivate = false
        }
        // Stay above application windows while allowing pop-up menus to open
        // above this panel, including the menu used to leave this mode.
        window.level = state.panelMode.staysOnTop ? .statusBar : .normal
        window.animationBehavior = .none
        applySettledFrame(to: window)
    }

    private func applySettledFrame(to window: NSWindow) {
        guard window !== leaderboardWindow, window === hosting.view.window else { return }
        guard let settled = settledPopoverFrame, !isApplyingSettledFrame else { return }
        guard !framesMatch(window.frame, settled) else { return }
        guard framePinAttempts < 8 else { return }
        framePinAttempts += 1
        isApplyingSettledFrame = true
        window.setFrame(settled, display: false, animate: false)
        isApplyingSettledFrame = false
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }

    /// A wide panel anchored to a right-side status item sits flush with the
    /// screen edge. The top-right corner is then clipped, and a capture of that
    /// region comes back blank.
    private func frameInsetFromScreenEdges(_ frame: NSRect, screen: NSScreen?) -> NSRect {
        guard let screen else { return frame }
        let visible = screen.visibleFrame
        var frame = frame
        let margin: CGFloat = 8
        if frame.width > visible.width - margin * 2 {
            return frame
        }
        if frame.maxX > visible.maxX - margin {
            frame.origin.x -= frame.maxX - (visible.maxX - margin)
        }
        if frame.minX < visible.minX + margin {
            frame.origin.x = visible.minX + margin
        }
        return frame
    }

    private func installFramePin(on window: NSWindow) {
        guard !framePinInstalled else { return }
        framePinInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverWindowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverWindowDidMove(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func removeFramePin() {
        guard framePinInstalled else { return }
        framePinInstalled = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didMoveNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResizeNotification,
            object: nil
        )
    }

    private func removeFramePinAfterSettling() {
        framePinGeneration += 1
        let generation = framePinGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.framePinGeneration == generation else { return }
            self.removeFramePin()
        }
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        updatePanelWidth()
    }

    private func updatePanelWidth() {
        guard state.panelMode != .window else { return }
        let limit = maximumWidth
        if hosting.rootView.maximumWidth != limit {
            hosting.rootView = LeaderboardView(state: state, maximumWidth: limit)
        }
        let size = LeaderboardView.preferredSize(for: state, maximumWidth: limit)
        let width = size.width
        let height = size.height
        let oldWidth = popover.contentSize.width
        let oldHeight = popover.contentSize.height
        guard abs(width - oldWidth) > 0.5 || abs(height - oldHeight) > 0.5 else { return }

        let window = popover.isShown ? hosting.view.window : nil
        if let window {
            let delta = width - oldWidth
            let heightDelta = height - oldHeight
            var frame = window.frame
            frame.origin.x -= delta // Keep the right edge near the menu item.
            frame.origin.y -= heightDelta // Keep the top edge under the menu bar.
            frame.size.width += delta
            frame.size.height += heightDelta
            settledPopoverFrame = frameInsetFromScreenEdges(frame, screen: window.screen)
            framePinAttempts = 0
            installFramePin(on: window)
        }

        hosting.preferredContentSize = size
        popover.contentSize = size

        if let window {
            applySettledFrame(to: window)
            removeFramePinAfterSettling()
        }
    }

    /// AppKit re-anchors after the level drop. Snap back before that frame paints.
    @objc private func popoverWindowDidMove(_ notification: Notification) {
        guard popover.isShown, let window = notification.object as? NSWindow,
              window === hosting.view.window, window !== leaderboardWindow else { return }
        applySettledFrame(to: window)
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        !AppUpdater.shared.isPresentingUpdate
    }

    func popoverWillShow(_ notification: Notification) {
        settledPopoverFrame = nil
        framePinAttempts = 0
        guard revealAfterSettle else { return }
        popover.contentViewController?.view.window?.alphaValue = 0
    }

    func popoverDidShow(_ notification: Notification) {
        if revealAfterSettle {
            popover.contentViewController?.view.window?.alphaValue = 0
        }
        settlePopoverWindow()
        if let window = popover.contentViewController?.view.window {
            installFramePin(on: window)
        }
        // AppKit can reapply the menu-bar level after show. Pin again, then reveal.
        DispatchQueue.main.async { [weak self] in
            self?.settlePopoverWindow()
            self?.revealPopoverIfNeeded()
        }
        // Only the open-time re-anchor should be pinned. A later show must not
        // have its pin removed by this timer.
        removeFramePinAfterSettling()
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissMonitor()
        framePinGeneration += 1
        removeFramePin()
        settledPopoverFrame = nil
        revealAfterSettle = false
        // A control that was hovered at close never reports its exit.
        PointingHandCursorRegistry.shared.reset()
    }

    private func revealPopoverIfNeeded() {
        guard revealAfterSettle, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        applySettledFrame(to: window)
        revealAfterSettle = false
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        updateDismissMonitor()
        AppUpdater.shared.presentIfReady()
        presentClaudeKeychainConsentIfNeeded()
    }

    private func presentClaudeKeychainConsentIfNeeded() {
        guard state.isClaudeKeychainConsentPending, !isPresentingClaudeKeychainConsent,
              let window = state.panelMode == .window ? leaderboardWindow : hosting.view.window,
              window.isVisible, window.alphaValue > 0, window.attachedSheet == nil else { return }
        isPresentingClaudeKeychainConsent = true
        let language = state.selectedLanguage
        let alert = ClaudeKeychainConsentAlert.make(language: language)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isPresentingClaudeKeychainConsent = false
            if response == .alertFirstButtonReturn {
                self.state.allowClaudeKeychainAccess()
            } else {
                self.state.declineClaudeKeychainAccess()
            }
        }
    }

    @objc private func windowSheetDidEnd(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.presentClaudeKeychainConsentIfNeeded()
        }
    }

    @objc private func togglePopover() {
        if AppUpdater.shared.isPresentingUpdate {
            AppUpdater.shared.focusPreparedUpdateFromMenuClick()
            return
        }
        if state.panelMode == .window {
            showLeaderboardWindow()
            state.refreshFromMenuClick()
            return
        }
        if popover.isShown {
            closePopover()
            return
        }

        // Show first, refresh second, so nothing synchronous stands between
        // the click and the popover appearing. Stay transparent until the
        // post-show frame pin has landed.
        if let button = statusItem.button {
            updatePanelWidth()
            revealAfterSettle = true
            popover.contentViewController?.view.window?.alphaValue = 0
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        state.refreshFromMenuClick()
    }

    private func closePopover() {
        guard !AppUpdater.shared.isPresentingUpdate else { return }
        removeDismissMonitor()
        popover.performClose(nil)
    }

    private func updatePresentationMode() {
        guard presentedMode != state.panelMode else { return }
        let wasVisible = popover.isShown || leaderboardWindow?.isVisible == true || leaderboardWindow?.isMiniaturized == true
        presentedMode = state.panelMode
        if presentedMode == .window {
            closePopover()
            if wasVisible { showLeaderboardWindow() }
        } else if let window = leaderboardWindow {
            // Leave native full-screen/Split View before moving back to a
            // menu-bar popover, rather than reparenting a full-screen window.
            if window.styleMask.contains(.fullScreen) {
                reopenPopoverAfterFullScreen = wasVisible
                window.toggleFullScreen(nil)
            } else {
                lastLeaderboardWindowFrame = window.frame
                window.orderOut(nil)
                if wasVisible { showPopover() }
            }
        }
        // Popover-to-popover changes reuse the visible panel. Apply the new
        // level immediately and keep its anchor stable while AppKit settles.
        if popover.isShown, let window = hosting.view.window {
            settledPopoverFrame = window.frame
            framePinAttempts = 0
            installFramePin(on: window)
            settlePopoverWindow()
            removeFramePinAfterSettling()
        }
    }

    private var reopenPopoverAfterFullScreen = false

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === leaderboardWindow,
              state.panelMode != .window else { return }
        lastLeaderboardWindowFrame = window.frame
        window.orderOut(nil)
        if reopenPopoverAfterFullScreen {
            reopenPopoverAfterFullScreen = false
            showPopover()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !AppUpdater.shared.isPresentingUpdate
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === leaderboardWindow,
           !window.styleMask.contains(.fullScreen) {
            lastLeaderboardWindowFrame = window.frame
        }
        PointingHandCursorRegistry.shared.reset()
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        updatePanelWidth()
        revealAfterSettle = true
        popover.contentViewController?.view.window?.alphaValue = 0
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showLeaderboardWindow() {
        var initialFrame: NSRect?
        if leaderboardWindow == nil {
            let screen = statusItem.button?.window?.screen ?? NSScreen.main
            let contentSize = LeaderboardView.preferredSize(for: state, maximumWidth: maximumWidth)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "AI BenchGauge"
            window.identifier = NSUserInterfaceItemIdentifier("ai-benchgauge.leaderboard-window")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = .normal
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
            window.contentMinSize = NSSize(width: 600, height: 380)
            let controller = NSHostingController(rootView: LeaderboardWindowView(state: state))
            controller.sizingOptions = []
            window.contentViewController = controller
            // Installing a GeometryReader host reduces the window to its
            // minimum size. Restore the shared panel size after mounting.
            window.setContentSize(contentSize)
            if let screen = screen ?? window.screen {
                let visible = screen.visibleFrame
                var frame = window.frame
                frame.origin = NSPoint(x: visible.midX - frame.width / 2,
                                       y: visible.midY - frame.height / 2)
                window.setFrame(frame, display: false)
            }
            initialFrame = window.frame
            leaderboardWindow = window
        }
        guard let window = leaderboardWindow else { return }
        let frame = lastLeaderboardWindowFrame ?? initialFrame
        lastLeaderboardWindowFrame = nil
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        presentClaudeKeychainConsentIfNeeded()
        // Hosting layout can recenter a previously hidden window when it is
        // shown again. Restore the user's frame once after that layout pass.
        // Subsequent moves/resizes are entirely owned by the user and macOS.
        guard let frame else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.state.panelMode == .window,
                  window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func closeIfUnfocused() {
        guard state.closesOnFocusLoss, popover.isShown,
              (popover.contentViewController?.view.window?.alphaValue ?? 0) > 0 else { return }
        closePopover()
    }

    private func updateDismissMonitor() {
        guard state.closesOnFocusLoss, popover.isShown,
              (popover.contentViewController?.view.window?.alphaValue ?? 0) > 0 else {
            removeDismissMonitor()
            return
        }
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeIfUnfocused()
            }
        }
    }

    private func removeDismissMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

}

@main
enum LeaderboardApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
