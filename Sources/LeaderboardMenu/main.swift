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
final class StatusBarController: NSObject {
    @IBOutlet private var button: NSStatusBarButton?
    private let popover = NSPopover()
    private let state: AppState
    private let statusItem: NSStatusItem
    private var outsideClickMonitor: Any?

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // .applicationDefined instead of .transient: a transient popover closes
        // as soon as a drop-down Menu opens its own window outside the popover,
        // which swallows the menu item action that opens the purchase link.
        popover.behavior = .applicationDefined
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.popover.performClose(nil)
            self?.popover.contentViewController?.view.window?.alphaValue = 1
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.alphaValue = 1
            startOutsideClickMonitor()
        }
        state.refreshFromMenuClick()
    }

    private func closePopover() {
        popover.performClose(nil)
        stopOutsideClickMonitor()
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        // Global monitor only sees events delivered to other apps, so clicks
        // inside the popover and its menus keep it open.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
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
