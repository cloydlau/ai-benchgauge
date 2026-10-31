import SwiftUI
import ImageIO
import LeaderboardKit

@MainActor
struct MobileCategoryBar: View {
    @Binding var category: LeaderboardCategory
    let categories: [LeaderboardCategory]
    let language: AppLanguage
    let accent: Color
    let select: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var dragIndex: Int?
    private static let icons: [String: CGImage] = LeaderboardCategory.allCases.reduce(into: [:]) { images, category in
        guard let url = Bundle.module.url(forResource: category.rawValue, withExtension: "png", subdirectory: "CategoryIcons"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        images[category.rawValue] = image
    }
    private var selectedCategory: LeaderboardCategory {
        dragIndex.flatMap { categories.indices.contains($0) ? categories[$0] : nil } ?? category
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(categories, id: \.self) { item in
                Button {
                    select()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { category = item }
                } label: {
                    VStack(spacing: 4) {
                        if item == .price {
                            Image(systemName: "tag").font(.system(size: 18)).foregroundStyle(accent)
                        } else if let icon = Self.icons[item.rawValue] {
                            Image(decorative: icon, scale: 3)
                                .renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                                .foregroundStyle(accent)
                        }
                        Text(LeaderboardPresentation.title(item, language: language)).font(.system(size: 10, weight: selectedCategory == item ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(selectedCategory == item ? accent : Color.secondary)
                    .background {
                        if selectedCategory == item {
                            Circle().fill(BrandTheme.selection(for: colorScheme)).frame(width: 50, height: 50).matchedGeometryEffect(id: "selection", in: selection)
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
        .modifier(MobileTabDrag(count: categories.count, preview: $dragIndex,
            begin: select) { index in
                guard categories.indices.contains(index) else { return }
                let item = categories[index]
                guard item != category else { return }
                select()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { category = item }
            })
        .onChange(of: categories) { _, _ in dragIndex = nil }
        .padding(4)
        .modifier(MobileCategoryGlass())
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        .frame(maxWidth: 500)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("category")
    }
}

/// Keep the neutral tint separate from the system's refraction and touch response.
private struct MobileCategoryGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(.gray.opacity(colorScheme == .dark ? 0.16 : 0.08)).interactive(), in: Capsule())
        } else {
            content.background {
                Capsule()
                    .fill(reduceTransparency ? AnyShapeStyle(BrandTheme.surface(for: colorScheme)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        Capsule().fill(.gray.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    }
                    .overlay {
                        Capsule().strokeBorder(LinearGradient(
                            colors: [.white.opacity(colorScheme == .dark ? 0.32 : 0.8),
                                     .white.opacity(0.04), .white.opacity(colorScheme == .dark ? 0.12 : 0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A drag selects the segment underneath the finger. Preview locally and
/// commit once on release, so crossing categories never starts extra fetches.
@MainActor
struct MobileTabDrag: ViewModifier {
    let count: Int
    @Binding var preview: Int?
    var enabled = true
    var begin: () -> Void = {}
    let select: (Int) -> Void
    @State private var width: CGFloat = 0
    @State private var axis = LeaderboardCube.DragAxis.undecided
    @GestureState private var touching = false

    private func index(at x: CGFloat) -> Int? {
        guard width > 0, count > 0 else { return nil }
        return min(count - 1, max(0, Int(floor(x / width * CGFloat(count)))))
    }
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { width = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, value in
                            width = value; preview = nil; axis = .undecided
                        }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    guard enabled else { preview = nil; return }
                    if axis == .undecided {
                        let x = abs(value.translation.width), y = abs(value.translation.height)
                        if x >= 8 && x > y * 1.25 { axis = .horizontal; begin() }
                        else if y >= 8 { axis = .vertical }
                    }
                    guard axis == .horizontal else { return }
                    preview = index(at: value.location.x)
                }
                .onEnded { value in
                    let destination = axis == .horizontal && enabled ? index(at: value.location.x) : nil
                    preview = nil; axis = .undecided
                    if let destination { select(destination) }
                })
            .onChange(of: touching) { _, active in
                // GestureState resets even when the system cancels a touch.
                if !active { preview = nil; axis = .undecided }
            }
            .onDisappear { preview = nil; axis = .undecided }
    }
}
