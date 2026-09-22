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

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // .applicationDefined instead of .transient: a transient popover closes
        // as soon as a drop-down Menu opens its own window outside the popover,
        // which swallows the menu item action that opens the purchase link.
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: LeaderboardView(state: state)
        )
        popover.contentSize = NSSize(
            width: LeaderboardView.contentWidth,
            height: LeaderboardView.contentHeight
        )

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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.popover.performClose(nil)
            self?.popover.contentViewController?.view.window?.alphaValue = 1
        }
    }

    /// A status-item popover is a child of the menu-bar window, so it inherits
    /// status-bar level and nothing else can cover it. Detach that relationship
    /// after show and drop to the normal window level. It still comes forward
    /// when opened; later clicks on other windows can then cover it.
    private func allowOtherWindowsToCoverPopover() {
        guard popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        let frame = window.frame
        window.parent?.removeChildWindow(window)
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = false
            panel.hidesOnDeactivate = false
        }
        window.level = .normal
        if window.frame != frame {
            window.setFrame(frame, display: false)
        }
        insetPopoverFromScreenEdges(window)
        if bringPopoverForwardOnShow {
            window.orderFrontRegardless()
            bringPopoverForwardOnShow = false
        }
    }

    /// A 1300pt panel anchored to a right-side status item sits flush with the
    /// screen edge. The top-right corner is then clipped, and a capture of that
    /// region comes back blank.
    private func insetPopoverFromScreenEdges(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        let margin: CGFloat = 8
        if frame.width > visible.width - margin * 2 {
            return
        }
        if frame.maxX > visible.maxX - margin {
            frame.origin.x -= frame.maxX - (visible.maxX - margin)
        }
        if frame.minX < visible.minX + margin {
            frame.origin.x = visible.minX + margin
        }
        if frame != window.frame {
            window.setFrame(frame, display: false)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        allowOtherWindowsToCoverPopover()
        // AppKit can reapply the menu-bar level after the show animation.
        DispatchQueue.main.async { [weak self] in
            self?.allowOtherWindowsToCoverPopover()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }

        // Show first, refresh second, so nothing synchronous stands between
        // the click and the popover appearing.
        if let button = statusItem.button {
            bringPopoverForwardOnShow = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.alphaValue = 1
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
