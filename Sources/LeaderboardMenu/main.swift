import AppKit
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
    /// Only a real menu-bar click should order the popover in front.
    /// Pre-warm shows it invisibly and must not surface that window.
    private var bringPopoverForwardOnShow = false
    /// Real clicks stay transparent until the post-show frame pin lands.
    private var revealAfterSettle = false
    /// Frame captured after AppKit anchors the popover, plus the screen-edge
    /// inset. Later level resets must not replace this with a shifted frame.
    private var settledPopoverFrame: NSRect?
    private var isApplyingSettledFrame = false
    private var framePinInstalled = false

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // .applicationDefined instead of .transient: a transient popover closes
        // as soon as a drop-down Menu opens its own window outside the popover,
        // which swallows the menu item action that opens the purchase link.
        popover.behavior = .applicationDefined
        // A size or origin change while animates is true replays the anchor
        // slide. That second slide is the down-left twitch after open.
        popover.animates = false
        popover.delegate = self
        let contentSize = NSSize(
            width: LeaderboardView.contentWidth,
            height: LeaderboardView.contentHeight
        )
        let hosting = NSHostingController(rootView: LeaderboardView(state: state))
        // Fixed panel. Tracking preferredContentSize lets SwiftUI resize the
        // popover after show, and a right-side anchor then shifts it down-left.
        hosting.sizingOptions = []
        hosting.preferredContentSize = contentSize
        popover.contentViewController = hosting
        popover.contentSize = contentSize

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "AI Leaderboards"
            )
            button.target = self
            button.action = #selector(togglePopover)
        }

        // Pre-warm: create the popover window and run the first SwiftUI
        // layout pass at launch (invisibly), so the first click opens
        // instantly instead of paying that cost on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.prewarmPopover()
        }
    }

    private func prewarmPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        bringPopoverForwardOnShow = false
        revealAfterSettle = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.revealAfterSettle else { return }
            self.popover.performClose(nil)
            self.popover.contentViewController?.view.window?.alphaValue = 1
        }
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

    /// A 1300pt panel anchored to a right-side status item sits flush with the
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

    /// AppKit re-anchors after the level drop. Snap back before that frame paints.
    @objc private func popoverWindowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        applySettledFrame(to: window)
    }

    func popoverWillShow(_ notification: Notification) {
        settledPopoverFrame = nil
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
    }

    func popoverDidClose(_ notification: Notification) {
        removeFramePin()
        settledPopoverFrame = nil
        revealAfterSettle = false
    }

    private func revealPopoverIfNeeded() {
        guard revealAfterSettle, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        applySettledFrame(to: window)
        revealAfterSettle = false
        bringPopoverForwardOnShow = false
        window.alphaValue = 1
        window.orderFrontRegardless()
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
            bringPopoverForwardOnShow = true
            revealAfterSettle = true
            popover.contentViewController?.view.window?.alphaValue = 0
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        state.refreshFromMenuClick()
    }

    private func closePopover() {
        popover.performClose(nil)
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
