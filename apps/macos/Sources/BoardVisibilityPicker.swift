import AppKit
import SwiftUI
import LeaderboardCore

/// Checkbox edits belong to the popover until Confirm is pressed. Dismissing
/// it never persists preferences or starts a leaderboard refresh.
struct BoardVisibilityPicker: NSViewRepresentable {
    let language: AppLanguage
    let category: LeaderboardCategory
    let selections: [String: [String]]
    let onConfirm: ([String: [String]]) -> Void

    func makeNSView(context: Context) -> BoardVisibilityButton { BoardVisibilityButton() }
    func updateNSView(_ button: BoardVisibilityButton, context: Context) {
        button.configure(language: language, category: category, selections: selections, onConfirm: onConfirm)
    }
}

@MainActor
final class BoardVisibilityButton: NSButton, NSPopoverDelegate {
    private var language = AppLanguage.english
    private var category = LeaderboardCategory.general
    private var selections: [String: [String]] = [:]
    private var onConfirm: ([String: [String]]) -> Void = { _ in }
    private(set) var selectionPopover: NSPopover?

    init() {
        super.init(frame: .zero)
        isBordered = false
        font = .systemFont(ofSize: 11)
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        imagePosition = .imageTrailing
        imageScaling = .scaleProportionallyDown
        identifier = NSUserInterfaceItemIdentifier("board-visibility-menu")
        target = self
        action = #selector(openSelection)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(language: AppLanguage, category: LeaderboardCategory, selections: [String: [String]],
                   onConfirm: @escaping ([String: [String]]) -> Void) {
        // A category/language change closes an obsolete draft without applying it.
        if self.category != category || self.language != language { closeSelection() }
        self.language = language
        self.category = category
        self.selections = selections
        self.onConfirm = onConfirm
        title = language.text("Leaderboards", "显示榜单")
        toolTip = language.text("Choose leaderboards, then confirm. Keep at least one.", "选择榜单后点击确认，至少保留一个。")
        invalidateIntrinsicContentSize()
    }

    @objc private func openSelection() {
        if let selectionPopover, selectionPopover.isShown { closeSelection(); return }
        let popover = NSPopover()
        let controller = NSViewController()
        controller.view = BoardVisibilitySelectionView(language: language, category: category, selections: selections,
            onConfirm: { [weak self] kinds in
                self?.closeSelection()
                self?.onConfirm(kinds)
            }, onCancel: { [weak self] in self?.closeSelection() })
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        selectionPopover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    private func closeSelection() {
        let closing = selectionPopover
        selectionPopover = nil
        closing?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, selectionPopover === closed else { return }
        selectionPopover = nil
    }
}

@MainActor
final class BoardVisibilitySelectionView: NSView {
    private let onConfirm: ([String: [String]]) -> Void
    private let onCancel: () -> Void
    private let choices: [(category: LeaderboardCategory, kind: LeaderboardKind)]
    private var draft: [String: [String]]
    private(set) var checkboxes: [NSButton] = []
    let confirmButton: NSButton
    let cancelButton: NSButton

    init(language: AppLanguage, category: LeaderboardCategory, selections: [String: [String]],
         onConfirm: @escaping ([String: [String]]) -> Void, onCancel: @escaping () -> Void) {
        let categories = [category] + LeaderboardCategory.allCases.filter { $0 != category }
        choices = categories.flatMap { item in item.boardKinds.map { (item, $0) } }
        draft = DesktopBoardSelection.normalized(selections)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        confirmButton = NSButton(title: language.text("Confirm", "确认"), target: nil, action: nil)
        cancelButton = NSButton(title: language.text("Cancel", "取消"), target: nil, action: nil)
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 10
        for (index, choice) in choices.enumerated() {
            let kind = choice.kind
            if index == 0 || choices[index - 1].category != choice.category {
                let heading = NSTextField(labelWithString: LeaderboardPresentation.title(choice.category, language: language))
                heading.font = .systemFont(ofSize: 11, weight: .semibold)
                heading.textColor = .secondaryLabelColor
                list.addArrangedSubview(heading)
            }
            let title = LeaderboardPresentation.boardSelectionTitle(kind, language: language)
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
            checkbox.tag = index
            checkbox.font = .systemFont(ofSize: 12)
            checkbox.identifier = NSUserInterfaceItemIdentifier("board-visibility-\(kind.rawValue)")
            checkboxes.append(checkbox)
            list.addArrangedSubview(checkbox)
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = list
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 330),
            scroll.heightAnchor.constraint(equalToConstant: 380),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        let note = NSTextField(labelWithString: language.text("Keep at least one leaderboard", "至少保留一个榜单"))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        let actions = NSStackView(views: [cancelButton, confirmButton])
        actions.spacing = 8
        stack.addArrangedSubview(actions)
        for (button, id, action) in [(cancelButton, "board-visibility-cancel", #selector(cancel)),
                                     (confirmButton, "board-visibility-confirm", #selector(confirm))] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.identifier = NSUserInterfaceItemIdentifier(id)
        }
        confirmButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            actions.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        updateCheckboxes()
        setFrameSize(fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateCheckboxes() {
        for (index, checkbox) in checkboxes.enumerated() {
            let choice = choices[index]
            let selected = DesktopBoardSelection.kinds(for: choice.category, saved: draft[choice.category.rawValue]).contains(choice.kind)
            checkbox.state = selected ? .on : .off
            checkbox.isEnabled = DesktopBoardSelection.count(in: draft) > 1 || !selected
        }
    }
    @objc private func toggle(_ sender: NSButton) {
        let choice = choices[sender.tag]
        draft = DesktopBoardSelection.toggling(choice.kind, in: choice.category, selections: draft)
        updateCheckboxes()
    }
    @objc private func confirm() { onConfirm(draft) }
    @objc private func cancel() { onCancel() }
}
