import AppKit
import Combine
import SwiftUI
import LeaderboardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stateController: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let cache: LeaderboardCache
        do {
            cache = LeaderboardCache(fileURL: try LeaderboardCache.defaultFileURL())
        } catch {
            cache = LeaderboardCache(fileURL: temporaryCacheURL())
        }
        let state = AppState(cache: cache)
        stateController = StatusBarController(state: state)
        state.start()
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ai-leaderboards.json", directoryHint: .inferFromPath)
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    @IBOutlet private var button: NSStatusBarButton?
    private let popover = NSPopover()
    private let state: AppState
    private let statusItem: NSStatusItem
    private let hosting: NSHostingController<LeaderboardView>
    private var stateObservation: AnyCancellable?
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

    private var maximumWidth: CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        return max(600, floor((screen?.visibleFrame.width ?? 1136) - 16))
    }

    init(state: AppState) {
        self.state = state
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
        let initialWidth = LeaderboardView.preferredWidth(for: state, maximumWidth: initialMaximumWidth)
        let contentSize = NSSize(
            width: initialWidth,
            height: LeaderboardView.preferredHeight(for: state, width: initialWidth, maximumWidth: initialMaximumWidth)
        )
        // Resize explicitly so AppKit cannot re-anchor the popover on each
        // SwiftUI layout pass.
        hosting.sizingOptions = []
        hosting.preferredContentSize = contentSize
        popover.contentViewController = hosting
        popover.contentSize = contentSize

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "AI Leaderboards"
            )
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateStatusItem()

        stateObservation = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.updatePanelWidth()
                self?.updateDismissMonitor()
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

        // Pre-warm: create the popover window and run the first SwiftUI
        // layout pass at launch (invisibly), so the first click opens
        // instantly instead of paying that cost on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.prewarmPopover()
        }
    }

    private func prewarmPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
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

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard !state.quotaNeedsCCSwitch, !state.quotaUnavailable,
              state.quotaUpdatedAt != nil,
              let current = state.quotaChips.first(where: \.isCurrent),
              let quota = AccountQuotaFormatting.compactMenuBarQuota(for: current) else {
            button.title = ""
            button.toolTip = "AI Leaderboards"
            return
        }
        let fullName = current.shortName
        let compactName = fullName.count > 24 ? String(fullName.prefix(23)) + "…" : fullName
        button.title = "\(compactName) · \(quota)"
        button.toolTip = "AI Leaderboards · \(fullName) · \(quota)"
    }

    /// A status-item popover is a child of the menu-bar window, so it inherits
    /// status-bar level and nothing else can cover it. Detach that relationship
    /// after show and drop to the normal window level. It still comes forward
    /// when opened; later clicks on other windows can then cover it.
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
        window.level = .normal
        window.animationBehavior = .none
        applySettledFrame(to: window)
    }

    private func applySettledFrame(to window: NSWindow) {
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
        let limit = maximumWidth
        if hosting.rootView.maximumWidth != limit {
            hosting.rootView = LeaderboardView(state: state, maximumWidth: limit)
        }
        let width = LeaderboardView.preferredWidth(for: state, maximumWidth: limit)
        let height = LeaderboardView.preferredHeight(for: state, width: width, maximumWidth: limit)
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

        let size = NSSize(width: width, height: height)
        hosting.preferredContentSize = size
        popover.contentSize = size

        if let window {
            applySettledFrame(to: window)
            removeFramePinAfterSettling()
        }
    }

    /// AppKit re-anchors after the level drop. Snap back before that frame paints.
    @objc private func popoverWindowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        applySettledFrame(to: window)
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
    }

    private func revealPopoverIfNeeded() {
        guard revealAfterSettle, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        applySettledFrame(to: window)
        revealAfterSettle = false
        window.alphaValue = 1
        window.orderFrontRegardless()
        updateDismissMonitor()
    }

    @objc private func togglePopover() {
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
        removeDismissMonitor()
        popover.performClose(nil)
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
