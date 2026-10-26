#if canImport(SwiftUI)
import SwiftUI

@MainActor final class ModelDetailsUI: ObservableObject {
    @Published var copied = false
    @Published var expanded: [String: Bool] = [:]
    @Published var backToTop = false
}
private struct ModelDetailScrollOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
public struct ModelDetailsView: View {
    public let entry: LeaderboardEntry
    public let language: AppLanguage
    public let copyName: (String) -> Bool
    public let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state: ModelDetailsUI
    private let sections: [ModelDetailSection]
    public init(entry: LeaderboardEntry, language: AppLanguage, copyName: @escaping (String) -> Bool, close: @escaping () -> Void) {
        self.init(entry: entry, language: language, state: ModelDetailsUI(), copyName: copyName, close: close)
    }
    init(entry: LeaderboardEntry, language: AppLanguage, state: ModelDetailsUI, copyName: @escaping (String) -> Bool, close: @escaping () -> Void) {
        self.entry = entry; self.language = language; self.copyName = copyName; self.close = close
        self._state = StateObject(wrappedValue: state)
        func order(_ id: String) -> Int { ["limits": 0, "capabilities": 1, "modalities": 2, "general": 3, "source": 9][id] ?? 4 }
        self.sections = ModelDetails.sections(for: entry, language: language).enumerated().sorted {
            let a = order($0.element.id), b = order($1.element.id)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    func copyModelName() { if copyName(entry.name) { state.copied = true } }
    private func tr(_ key: String) -> String { ModelDetails.text(key, language: language) }
    private var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    private var card: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    private func symbol(_ id: String) -> String {
        if id == "limits" { return "chart.bar.xaxis" }
        if id == "capabilities" { return "square.grid.2x2" }
        if id.hasPrefix("provider-") { return "server.rack" }
        return id == "source" ? "info.circle" : "doc.text"
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("details")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(tr("close")).accessibilityIdentifier("close-model-details")
            }
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").font(.title3).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                Text(entry.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: copyModelName) {
                    Image(systemName: state.copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(state.copied ? tr("copied") : tr("copy"))
                    .accessibilityIdentifier("copy-model-name")
            }
            HStack(spacing: 6) {
                if let license = entry.modelMetadata?.license { badge(license) }
                if let date = entry.modelMetadata?.releaseDate { badge(date) }
            }
        }.padding(.horizontal, 20).padding(.bottom, 18)
    }
    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }
    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ModelDetailScrollOffset.self, value: geometry.frame(in: .named("model-details-scroll")).minY)
                        }.frame(height: 0).id("model-details-top")
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if case .string(let description) = entry.modelMetadata?.attributes?["description"] {
                                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).padding(.bottom, 6)
                            }
                            if sections.isEmpty { Text(tr("missing")).foregroundStyle(.secondary).padding(.vertical, 24) }
                            ForEach(sections) { section in sectionCard(section) }
                        }.padding(.horizontal, 20).padding(.bottom, 72)
                    }
                }.coordinateSpace(name: "model-details-scroll")
                    .onPreferenceChange(ModelDetailScrollOffset.self) { state.backToTop = $0 < -240 }
                    .overlay(alignment: .bottomTrailing) {
                        if state.backToTop {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("model-details-top", anchor: .top) }
                            } label: {
                                Image(systemName: "arrow.up.to.line").frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                            }.buttonStyle(.plain).shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                                .accessibilityLabel(tr("backToTop")).accessibilityIdentifier("model-details-back-to-top").padding(20)
                        }
                    }
            }
        }.background(background)
    }
    private func sectionCard(_ section: ModelDetailSection) -> some View {
        let binding = Binding(get: { state.expanded[section.id] ?? ["limits", "capabilities", "modalities"].contains(section.id) },
                              set: { state.expanded[section.id] = $0 })
        return DisclosureGroup(isExpanded: binding) {
            if section.id == "limits" || section.id == "capabilities" {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(row.label).font(.caption).foregroundStyle(.secondary)
                            Text(row.value).font(section.id == "limits" ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                }.padding(.top, 10)
            } else { detailRows(section.rows).padding(.top, 10) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(section.id)).font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(section.summary ?? "\(section.rows.count) \(tr("facts"))").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, 4)
        }.tint(.secondary).padding(14).background(card, in: RoundedRectangle(cornerRadius: 14))
    }
    func detailRows(_ rows: [ModelDetailRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 5) {
                    Divider().padding(.bottom, 6)
                    if !row.label.isEmpty { Text(row.label).font(.caption).foregroundStyle(.secondary) }
                    if let link = row.url.flatMap(URL.init(string:)) {
                        Link(row.value, destination: link).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(row.value).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }
        }
    }
}
#endif
