import AppKit
import SwiftUI
import LeaderboardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stateController: StatusBarController?
    private var snapshotController: PanelSnapshot?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let cache: LeaderboardCache
        do {
            cache = LeaderboardCache(fileURL: try LeaderboardCache.defaultFileURL())
        } catch {
            cache = LeaderboardCache(fileURL: temporaryCacheURL())
        }
        let state = AppState(cache: cache)
        if let outputURL = PanelSnapshot.outputURL(from: CommandLine.arguments) {
            snapshotController = PanelSnapshot(state: state, outputURL: outputURL)
            snapshotController?.start()
            return
        }
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

/// One-shot render of the real panel. Not a user-facing mode: `dev.sh` does
/// not pass `--snapshot`, and the process quits after writing the PNG.
@MainActor
final class PanelSnapshot: NSObject {
    private let state: AppState
    private let outputURL: URL
    private var window: NSWindow?
    private var startedAt = Date()

    init(state: AppState, outputURL: URL) {
        self.state = state
        self.outputURL = outputURL
    }

    static func outputURL(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--snapshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    func start() {
        let host = NSHostingController(rootView: LeaderboardView(state: state))
        let size = NSSize(width: LeaderboardView.contentWidth, height: LeaderboardView.contentHeight)
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 40, y: 120, width: size.width, height: size.height)
        let origin = NSPoint(
            x: visible.minX + max(0, (visible.width - size.width) / 2),
            y: visible.minY + max(0, (visible.height - size.height) / 2)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Leaderboards"
        window.contentViewController = host
        window.setContentSize(size)
        window.setFrameOrigin(origin)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        state.start()
        scheduleCapture()
    }

    private func scheduleCapture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.captureIfReady()
        }
    }

    private func captureIfReady() {
        let waited = Date().timeIntervalSince(startedAt)
        let chips = state.quotaChips
        let pending = chips.contains { chip in
            if case .pending = chip.status { return true }
            return false
        }
        let ready = !chips.isEmpty && !pending && state.quotaUpdatedAt != nil
        if !ready, !state.quotaUnavailable, waited < 22 {
            scheduleCapture()
            return
        }
        // One more turn so SwiftUI paints the resolved chips.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.writePNG()
        }
    }

    private func writePNG() {
        guard let view = window?.contentView else {
            fputs("snapshot: no view\n", stderr)
            NSApp.terminate(nil)
            return
        }
        view.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        guard let shot = PanelScreenshot.capture(view: view) else {
            fputs("snapshot: capture failed\n", stderr)
            NSApp.terminate(nil)
            return
        }
        do {
            try shot.png.write(to: outputURL, options: .atomic)
            fputs("snapshot: \(outputURL.path)\n", stderr)
        } catch {
            fputs("snapshot: \(error)\n", stderr)
        }
        NSApp.terminate(nil)
    }
}
