import AppKit
import SwiftUI
import LeaderboardCore

struct DataSourcesPicker: NSViewRepresentable {
    let language: AppLanguage
    func makeNSView(context: Context) -> DataSourcesButton { DataSourcesButton() }
    func updateNSView(_ button: DataSourcesButton, context: Context) { button.configure(language: language) }
}

@MainActor
final class DataSourcesButton: NSButton, NSPopoverDelegate {
    private var language = AppLanguage.english
    private(set) var sourcesPopover: NSPopover?

    init() {
        super.init(frame: .zero)
        isBordered = false
        font = .systemFont(ofSize: 11)
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        imagePosition = .imageTrailing
        imageScaling = .scaleProportionallyDown
        identifier = NSUserInterfaceItemIdentifier("data-sources-menu")
        target = self
        action = #selector(toggleSources)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(language: AppLanguage) {
        if self.language != language { sourcesPopover?.performClose(nil) }
        self.language = language
        title = language.text("Data sources", "数据来源")
        toolTip = language.text("Leaderboard data sources", "榜单数据来源")
        invalidateIntrinsicContentSize()
    }

    @objc private func toggleSources() {
        if let sourcesPopover, sourcesPopover.isShown { sourcesPopover.performClose(nil); return }
        let popover = NSPopover()
        let controller = NSViewController()
        controller.view = DataSourcesListView(language: language) { [weak self] url in
            self?.sourcesPopover?.performClose(nil)
            NSWorkspace.shared.open(url)
        }
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        sourcesPopover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, sourcesPopover === closed { sourcesPopover = nil }
    }
}

@MainActor
final class DataSourcesListView: NSView {
    // Source discovery is independent of the selected category, cached data and visibility preferences.
    static let sources: [LeaderboardKind] = [.artificialAnalysis, .arenaText, .epochECI, .openRouterUsage, .vercelUsage, .cloudbaseUsage]
    private(set) var linkButtons: [NSButton] = []
    private let onOpen: (URL) -> Void

    init(language: AppLanguage, onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let heading = NSTextField(labelWithString: language.text("Data sources", "数据来源"))
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(heading)
        for (index, kind) in Self.sources.enumerated() {
            if kind == .openRouterUsage {
                let separator = NSBox(); separator.boxType = .separator
                stack.addArrangedSubview(separator)
            }
            let button = NSButton(title: kind.sourcePrefix + " ↗", target: self, action: #selector(openSource(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 12)
            button.tag = index
            button.identifier = NSUserInterfaceItemIdentifier("data-source-\(kind.rawValue)")
            button.toolTip = kind.sourceURL.absoluteString
            linkButtons.append(button)
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        setFrameSize(fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func openSource(_ sender: NSButton) { onOpen(Self.sources[sender.tag].sourceURL) }
}
