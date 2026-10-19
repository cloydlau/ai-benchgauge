import AppKit
import SwiftUI
import LeaderboardCore

/// Checkbox edits belong to the popover until Confirm is pressed. Dismissing
/// it never persists preferences or starts a leaderboard refresh.
struct BoardVisibilityPicker: NSViewRepresentable {
    let language: AppLanguage
    let category: LeaderboardCategory
    let selected: [LeaderboardKind]
    let onConfirm: ([LeaderboardKind]) -> Void

    func makeNSView(context: Context) -> BoardVisibilityButton { BoardVisibilityButton() }
    func updateNSView(_ button: BoardVisibilityButton, context: Context) {
        button.configure(language: language, category: category, selected: selected, onConfirm: onConfirm)
    }
}

@MainActor
final class BoardVisibilityButton: NSButton, NSPopoverDelegate {
    private var language = AppLanguage.english
    private var category = LeaderboardCategory.general
    private var selected: [LeaderboardKind] = []
    private var onConfirm: ([LeaderboardKind]) -> Void = { _ in }
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

    func configure(language: AppLanguage, category: LeaderboardCategory, selected: [LeaderboardKind],
                   onConfirm: @escaping ([LeaderboardKind]) -> Void) {
        // A category/language change closes an obsolete draft without applying it.
        if self.category != category || self.language != language { closeSelection() }
        self.language = language
        self.category = category
        self.selected = selected
        self.onConfirm = onConfirm
        title = language.text("Leaderboards", "显示榜单")
        toolTip = language.text("Choose leaderboards, then confirm. Keep at least one.", "选择榜单后点击确认，至少保留一个。")
        invalidateIntrinsicContentSize()
    }

    @objc private func openSelection() {
        if let selectionPopover, selectionPopover.isShown { closeSelection(); return }
        let popover = NSPopover()
        let controller = NSViewController()
        controller.view = BoardVisibilitySelectionView(language: language, category: category, selected: selected,
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
    private let onConfirm: ([LeaderboardKind]) -> Void
    private let onCancel: () -> Void
    private let choices: [LeaderboardKind]
    private var draft: Set<LeaderboardKind>
    private(set) var checkboxes: [NSButton] = []
    let confirmButton: NSButton
    let cancelButton: NSButton

    init(language: AppLanguage, category: LeaderboardCategory, selected: [LeaderboardKind],
         onConfirm: @escaping ([LeaderboardKind]) -> Void, onCancel: @escaping () -> Void) {
        choices = category.boardKinds
        draft = Set(DesktopBoardSelection.kinds(for: category, saved: selected.map(\.rawValue)))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        confirmButton = NSButton(title: language.text("Confirm", "确认"), target: nil, action: nil)
        cancelButton = NSButton(title: language.text("Cancel", "取消"), target: nil, action: nil)
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for (index, kind) in choices.enumerated() {
            let title = kind.sourceLinkTitle + " · " + LeaderboardPresentation.explanation(kind, language: language)
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
            checkbox.tag = index
            checkbox.font = .systemFont(ofSize: 12)
            checkbox.identifier = NSUserInterfaceItemIdentifier("board-visibility-\(kind.rawValue)")
            checkboxes.append(checkbox)
            stack.addArrangedSubview(checkbox)
        }
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
            let selected = draft.contains(choices[index])
            checkbox.state = selected ? .on : .off
            checkbox.isEnabled = draft.count > 1 || !selected
        }
    }
    @objc private func toggle(_ sender: NSButton) {
        let kind = choices[sender.tag]
        if draft.contains(kind) { if draft.count > 1 { draft.remove(kind) } }
        else { draft.insert(kind) }
        updateCheckboxes()
    }
    @objc private func confirm() { onConfirm(choices.filter { draft.contains($0) }) }
    @objc private func cancel() { onCancel() }
}
