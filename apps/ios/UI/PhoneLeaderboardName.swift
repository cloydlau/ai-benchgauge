#if os(iOS)
import SwiftUI
import UIKit
import LeaderboardKit

@MainActor
struct PhoneLeaderboardName: View {
    let name: String
    let language: AppLanguage
    let identifier: String
    let openDetails: () -> Void
    @State private var textSize = CGSize.zero
    private struct FullName: Identifiable {
        let name: String
        var id: String { name }
    }
    @State private var fullName: FullName?

    private var isTruncated: Bool {
        guard textSize.width > 0 else { return false }
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.text = name
        let fullSize = label.sizeThatFits(CGSize(width: textSize.width, height: .greatestFiniteMagnitude))
        return fullSize.height > textSize.height + 1
    }

    private func showFullName() {
        guard isTruncated else { return }
        fullName = FullName(name: name)
    }

    var body: some View {
        Button {
            // Presenting the full-name bubble must not also open a sheet.
            if fullName == nil { openDetails() }
        } label: {
            Text(name).font(.subheadline).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { textSize = geometry.size }
                            .onChange(of: geometry.size) { _, size in textSize = size }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name + language.text(", view model details", "，查看模型详情"))
        .accessibilityIdentifier(identifier)
        .accessibilityHint(isTruncated ? language.text("Long press to view the full name", "长按查看完整名称") : "")
        .accessibilityActions {
            if isTruncated {
                Button(language.text("Show full name", "显示完整名称"), action: showFullName)
            }
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
            .onEnded { _ in showFullName() })
        .popover(item: $fullName, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) { selected in
            Text(selected.name).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(14)
                .frame(idealWidth: 280, maxWidth: 280, alignment: .leading)
                .accessibilityLabel(selected.name)
                .accessibilityIdentifier("full-name-\(identifier)")
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
