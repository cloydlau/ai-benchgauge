import SwiftUI
import LeaderboardKit

@MainActor
struct LeaderboardSettingsView: View {
    @ObservedObject var store: LeaderboardPadStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private func tr(_ en: String, _ zh: String) -> String { store.language.text(en, zh) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Keep at least one leaderboard in each category.", "每个分类至少保留一个榜单。"))
                        .foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text(tr("Leaderboards", "显示榜单"))
                        Spacer()
                        Button(tr("Reset", "重置")) { store.resetBoardSelections() }
                            .textCase(nil).accessibilityIdentifier("reset-boards")
                    }
                }
                ForEach(LeaderboardCategory.allCases, id: \.self) { category in
                    Section(LeaderboardPresentation.title(category, language: store.language)) {
                        ForEach(category.boardKinds, id: \.self) { kind in
                            let kinds = store.boardKinds(for: category)
                            let selected = kinds.contains(kind)
                            let required = selected && kinds.count == 1
                            Button { store.toggleBoard(kind, in: category) } label: {
                                HStack(spacing: 12) {
                                    if let sourceID = SourceTabTheme.sourceID(for: kind) {
                                        SourceBrandIcon(sourceID: sourceID, dark: colorScheme == .dark, size: 24)
                                    }
                                    Text(LeaderboardPresentation.columnTitle(kind, language: store.language))
                                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                        .opacity(required ? 0.45 : 1)
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(required)
                            .accessibilityIdentifier("board-setting-\(kind.rawValue)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(tr("Settings", "设置"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "完成")) { dismiss() }.accessibilityIdentifier("settings-done")
                }
            }
        }
        .accessibilityIdentifier("settings-page")
        .environment(\.locale, store.language.locale)
        .preferredColorScheme(store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil)
    }
}
