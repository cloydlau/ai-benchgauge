import AppKit
import SwiftUI
import LeaderboardCore

@MainActor
final class DesktopLeaderboardSearchState: ObservableObject {
    @Published var query = ""
    @Published var isExpanded = false
}

/// The overlay keeps the navigation's width stable and expands from its right edge.
struct DesktopLeaderboardSearch: NSViewRepresentable {
    @ObservedObject var state: DesktopLeaderboardSearchState
    let language: AppLanguage

    func makeNSView(context: Context) -> DesktopLeaderboardSearchView { DesktopLeaderboardSearchView() }
    func updateNSView(_ view: DesktopLeaderboardSearchView, context: Context) {
        view.onQuery = { state.query = $0 }
        view.onExpansion = { state.isExpanded = $0 }
        view.configure(query: state.query, expanded: state.isExpanded,
            label: language.text("Search models", "搜索模型"))
    }
}

final class DesktopLeaderboardSearchView: NSView, NSSearchFieldDelegate {
    let button = NSButton()
    let field = NSSearchField()
    var onQuery: ((String) -> Void)?
    var onExpansion: ((Bool) -> Void)?
    private(set) var expanded = false
    private var animating = false
    nonisolated(unsafe) private var outsideClickMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        button.target = self; button.action = #selector(openSearch)
        button.identifier = NSUserInterfaceItemIdentifier("leaderboard-search-button")
        field.identifier = NSUserInterfaceItemIdentifier("leaderboard-search-input")
        field.font = .systemFont(ofSize: 12)
        field.sendsSearchStringImmediately = true
        field.target = self; field.action = #selector(searchChanged)
        field.delegate = self
        field.isHidden = true
        addSubview(button); addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification, object: window)
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.expanded, !self.isHiddenOrHasHiddenAncestor,
                      !self.visibleRect.isEmpty else { return }
                if event.window === self.window,
                   self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { return }
                self.endSearchEditing()
            }
            return event
        }
    }

    func configure(query: String, expanded: Bool, label: String) {
        button.toolTip = label; button.setAccessibilityLabel(label)
        field.placeholderString = label; field.setAccessibilityLabel(label)
        if field.stringValue != query { field.stringValue = query }
        setExpanded(expanded)
    }

    override func layout() {
        super.layout()
        button.frame = NSRect(x: max(0, bounds.width - 26), y: 0, width: 26, height: bounds.height)
        if !animating { field.frame = expanded ? bounds : button.frame }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // The collapsed overlay must let both native segmented controls receive clicks.
        if !expanded && !button.frame.contains(local) { return nil }
        return super.hitTest(point)
    }

    @objc private func openSearch() { onExpansion?(true); setExpanded(true) }
    @objc private func searchChanged() { onQuery?(field.stringValue) }
    func controlTextDidChange(_ notification: Notification) { searchChanged() }
    func controlTextDidEndEditing(_ notification: Notification) {
        collapseIfEmpty()
    }
    private func collapseIfEmpty() {
        guard expanded, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onExpansion?(false); setExpanded(false)
    }
    @objc private func windowResignedKey() { endSearchEditing() }
    private func endSearchEditing() {
        // Labels, table backgrounds and other non-focusable views do not end
        // AppKit field editing by themselves. Explicitly finish it on outside clicks.
        collapseIfEmpty()
        if let window, let editor = field.currentEditor(), window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { endSearchEditing() }
        return true
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        layoutSubtreeIfNeeded()
        expanded = value
        button.isHidden = value
        field.isHidden = false
        animating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            field.animator().frame = value ? bounds : button.frame
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animating = false
                self.field.isHidden = !self.expanded
                self.needsLayout = true
            }
        }
        if value {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.expanded, !self.isHiddenOrHasHiddenAncestor,
                      !self.visibleRect.isEmpty else { return }
                self.window?.makeFirstResponder(self.field)
            }
        }
    }
}
