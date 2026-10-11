#if os(iOS)
import SwiftUI
import UIKit

@MainActor
struct PhoneMenuItem {
    let title: String
    let identifier: String
    let action: @MainActor () -> Void
    var selected = false
}

/// A native primary-action menu provides a rectangular touch and accessibility
/// target, including after dismissing a sheet presented by a cube face.
@MainActor
struct PhoneMenuButton: UIViewRepresentable {
    let title: String
    let identifier: String
    let items: [PhoneMenuItem]
    var sourceTitle = ""
    var sources: [PhoneMenuItem] = []
    var label: String?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .secondaryLabel
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .caption1)
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        button.configuration?.title = title
        button.accessibilityLabel = label ?? title
        button.accessibilityIdentifier = identifier
        func menuAction(_ item: PhoneMenuItem) -> UIAction {
            UIAction(title: item.title, identifier: UIAction.Identifier(rawValue: item.identifier), state: item.selected ? .on : .off) { _ in
                MainActor.assumeIsolated { item.action() }
            }
        }
        var children: [UIMenuElement] = items.map(menuAction)
        if !sources.isEmpty {
            children.append(UIMenu(title: sourceTitle, options: .displayInline, children: sources.map(menuAction)))
        }
        button.menu = UIMenu(children: children)
    }
}
#endif
