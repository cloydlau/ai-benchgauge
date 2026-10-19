#if canImport(SwiftUI)
import SwiftUI

@MainActor final class ModelDetailsUI: ObservableObject {
    @Published var copied = false
}
public struct ModelDetailsView: View {
    public let entry: LeaderboardEntry
    public let language: AppLanguage
    public let copyName: (String) -> Bool
    public let close: () -> Void
    @StateObject private var state: ModelDetailsUI
    private let sections: [ModelDetailSection]
    public init(entry: LeaderboardEntry, language: AppLanguage, copyName: @escaping (String) -> Bool, close: @escaping () -> Void) {
        self.init(entry: entry, language: language, state: ModelDetailsUI(), copyName: copyName, close: close)
    }
    init(entry: LeaderboardEntry, language: AppLanguage, state: ModelDetailsUI, copyName: @escaping (String) -> Bool, close: @escaping () -> Void) {
        self.entry = entry; self.language = language; self.copyName = copyName; self.close = close
        self._state = StateObject(wrappedValue: state)
        self.sections = ModelDetails.sections(for: entry, language: language)
    }
    func copyModelName() {
        if copyName(entry.name) { state.copied = true }
    }
    private func tr(_ key: String) -> String { ModelDetails.text(key, language: language) }
    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr("details")).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel(tr("close")).accessibilityIdentifier("close-model-details")
                }
                HStack(alignment: .center, spacing: 10) {
                    Text(entry.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Button(action: copyModelName) {
                        Image(systemName: state.copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(state.copied ? tr("copied") : tr("copy"))
                        .accessibilityIdentifier("copy-model-name")
                }
            }.padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if sections.isEmpty {
                        Text(tr("missing")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                    ForEach(sections) { section in
                        GroupBox {
                            if let summary = section.summary {
                                DisclosureGroup {
                                    detailRows(section.rows).padding(.top, 10)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(section.title).font(.headline)
                                        Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(section.title).font(.headline)
                                    detailRows(section.rows)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.padding(20)
            }
        }
    }
    func detailRows(_ rows: [ModelDetailRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    if !row.label.isEmpty { Text(row.label).font(.caption).foregroundStyle(.secondary) }
                    if let link = row.url.flatMap(URL.init(string:)) {
                        Link(row.value, destination: link).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(row.value).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
