import AppKit
import LeaderboardCore

@MainActor
enum SourceDetailsAlert {
    static func make(title: String, content: String, language: AppLanguage) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        let scroll = SourceDetailsScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        scroll.text.string = content
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: language.text("Copy link", "复制链接"))
        return alert
    }
}

@MainActor
private final class SourceDetailsScrollView: NSScrollView {
    let text = NSTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        autohidesScrollers = true
        drawsBackground = false
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        documentView = text
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // NSAlert installs and sizes its accessory during the current turn.
        // Reset after that layout, before the user can scroll the new sheet.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            self.layoutSubtreeIfNeeded()
            self.contentView.scroll(to: .zero)
            self.reflectScrolledClipView(self.contentView)
        }
    }

    override func layout() {
        super.layout()
        guard let container = text.textContainer, let manager = text.layoutManager else { return }
        // A legacy vertical scroller can reduce the viewport after installation
        // in NSAlert. Fit the document to that width instead of its old frame.
        let width = max(1, contentView.bounds.width)
        text.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        text.setFrameSize(NSSize(width: width, height: max(text.frame.height, contentView.bounds.height)))
        container.containerSize = NSSize(width: max(1, width - 2 * text.textContainerInset.width),
            height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(contentView.bounds.height,
            ceil(manager.usedRect(for: container).maxY + 2 * text.textContainerInset.height))
        text.setFrameSize(NSSize(width: width, height: height))
    }
}
