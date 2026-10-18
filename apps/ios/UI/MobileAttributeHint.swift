#if os(iOS)
import SwiftUI

/// Keep compact symbols readable on touch screens without widening their columns.
struct MobileAttributeHint<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @State private var showing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { showing = true } label: {
            content().frame(minHeight: 44).contentShape(Rectangle()).accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { showing = false }
        }
        .popover(isPresented: $showing, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: 280)
                .accessibilityIdentifier("hint-\(identifier)")
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
