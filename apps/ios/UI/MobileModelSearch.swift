import SwiftUI
import LeaderboardKit

struct MobileModelSearchOrigin: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct MobileModelSearchBar: View {
    @Binding var query: String
    let focus: FocusState<Bool>.Binding
    let kind: LeaderboardKind
    let language: AppLanguage
    let pinned: Bool
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(language.text("Search models", "搜索模型"), text: $query)
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .focused(focus)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                #endif
                .onSubmit { focus.wrappedValue = false }
                .accessibilityIdentifier("model-search-input-\(kind.rawValue)")
            if !query.isEmpty {
                Button {
                    query = ""
                    focus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel(language.text("Clear search", "清空搜索"))
                .accessibilityIdentifier("model-search-clear-\(kind.rawValue)")
            }
            Button(language.text("Cancel", "取消"), action: close)
                .fixedSize().frame(minHeight: 28)
                .accessibilityIdentifier("model-search-cancel-\(kind.rawValue)")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .padding(.horizontal, pinned ? 0 : 8)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(Color.padBackground, in: RoundedRectangle(cornerRadius: pinned ? 0 : 6))
        .clipped()
    }
}
