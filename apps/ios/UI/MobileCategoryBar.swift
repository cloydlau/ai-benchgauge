import SwiftUI
import LeaderboardKit

@MainActor
struct MobileCategoryBar: View {
    @Binding var category: LeaderboardCategory
    let language: AppLanguage
    let select: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    private func icon(_ category: LeaderboardCategory) -> String {
        switch category {
        case .general: "square.grid.2x2"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .video: "video"
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardCategory.allCases, id: \.self) { item in
                Button {
                    select()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { category = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon(item)).font(.system(size: 18))
                        Text(LeaderboardPresentation.title(item, language: language)).font(.system(size: 11, weight: category == item ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(category == item ? BrandTheme.accent(for: colorScheme) : Color.secondary)
                    .background {
                        if category == item {
                            Capsule().fill(BrandTheme.selection(for: colorScheme)).matchedGeometryEffect(id: "selection", in: selection)
                                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel(LeaderboardPresentation.title(item, language: language))
                    .accessibilityIdentifier("category-\(item.rawValue)")
                    .accessibilityAddTraits(category == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        .frame(maxWidth: 500)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("category")
    }
}
