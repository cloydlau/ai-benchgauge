import AppKit
import SwiftUI
import LeaderboardCore

@MainActor
enum QuotaTrackingHelpAlert {
    static func make(language: AppLanguage) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = AppFeatureCopy.quotaTitle(language: language)
        alert.informativeText = AppFeatureCopy.quotaMessage(language: language)
        alert.addButton(withTitle: language.text("Got it", "知道了"))
        return alert
    }
}

/// The status popover must accept the first click on the help icon.
struct QuotaTrackingHelpButton: NSViewRepresentable {
    let language: AppLanguage
    let iconHeight: CGFloat
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: iconHeight, height: iconHeight)
    }
    func makeCoordinator() -> Coordinator { Coordinator(language: language) }
    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseHelpButton(title: "",
            target: context.coordinator, action: #selector(Coordinator.openHelp))
        button.isBordered = false
        button.setAccessibilityIdentifier("quota-tracking-help")
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.language = language
        button.toolTip = AppFeatureCopy.quotaHelpLabel(language: language)
        button.setAccessibilityLabel(AppFeatureCopy.quotaHelpLabel(language: language))
    }
    @MainActor final class Coordinator: NSObject {
        var language: AppLanguage
        init(language: AppLanguage) { self.language = language }
        @objc func openHelp() { QuotaTrackingHelpAlert.make(language: language).runModal() }
    }
}
private final class FirstMouseHelpButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
