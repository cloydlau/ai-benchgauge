import SwiftUI
import LeaderboardCore

struct PanelModePicker: NSViewRepresentable {
    let language: AppLanguage
    @Binding var selection: PanelMode

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> PanelModePopUpButton {
        let button = PanelModePopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .mini
        button.font = .systemFont(ofSize: 11)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(button)
        return button
    }

    func updateNSView(_ button: PanelModePopUpButton, context: Context) {
        context.coordinator.selection = $selection
        configure(button)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PanelModePopUpButton,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func configure(_ button: PanelModePopUpButton) {
        let titles = PanelMode.allCases.map { $0.title(language: language) }
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
            button.invalidateIntrinsicContentSize()
        }
        if let index = PanelMode.allCases.firstIndex(of: selection),
           button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
        button.setAccessibilityLabel(language.text("Display mode", "显示模式"))
        button.toolTip = language.text(
            "Keep open: stays open when you click elsewhere; click the menu bar icon again to close. Always on top: also stays above other windows. Close on blur: closes when you click elsewhere or switch apps. Window: move, resize, and use Split View.",
            "保持打开：点击其他位置不会关闭，再点菜单栏图标关闭。保持置顶：保持打开，并显示在其他窗口之上。失焦关闭：点击其他位置或切换应用时关闭。独立窗口：可拖动、调整大小和分屏。"
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<PanelMode>

        init(selection: Binding<PanelMode>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard PanelMode.allCases.indices.contains(index) else { return }
            selection.wrappedValue = PanelMode.allCases[index]
        }
    }
}

/// The popover can be visible without being key. Deliver the activating
/// click to the menu as well, so opening it never takes a second click.
final class PanelModePopUpButton: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
