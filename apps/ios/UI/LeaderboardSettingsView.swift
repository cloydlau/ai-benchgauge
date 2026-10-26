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
                    HStack(spacing: 8) {
                        ForEach(LeaderboardSwitchStyle.allCases, id: \.self) { style in
                            let selected = store.boardTransition == style
                            Button { store.boardTransition = style } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    BoardSwitchPreview(style: style, selected: selected)
                                    HStack(spacing: 3) {
                                        Text(style.title(store.language)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                        Spacer(minLength: 0)
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4)).font(.system(size: 12))
                                    }
                                    Text(style.subtitle(store.language)).font(.system(size: 10)).foregroundStyle(.secondary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .padding(.horizontal, 9).padding(.bottom, 12)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 1.5 : 0.5) }
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).foregroundStyle(.primary)
                            .accessibilityLabel(style.title(store.language))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("board-transition-\(style.rawValue)")
                        }
                    }.padding(.vertical, 4).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text(tr("Switch animation", "切换动效"))
                } footer: {
                    Text(tr("For swipes and tab switches in the single-board view.", "用于单榜视图的左右滑动与标签切换。"))
                }
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

private struct BoardSwitchPreview: View {
    let style: LeaderboardSwitchStyle
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0.3

    private func sheet(_ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(tint.opacity(0.8)).frame(width: 16, height: 4).padding(.bottom, 3)
            Capsule().fill(tint.opacity(0.24)).frame(height: 2)
            Capsule().fill(tint.opacity(0.24)).frame(width: 24, height: 2)
            Capsule().fill(tint.opacity(0.24)).frame(height: 2)
        }.padding(8).frame(width: 48, height: 58)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.3), lineWidth: 0.5) }
            .shadow(color: tint.opacity(0.08), radius: 4, y: 3)
    }
    var body: some View {
        ZStack {
            Ellipse().fill(Color.accentColor.opacity(0.08)).frame(width: 85, height: 65).blur(radius: 7)
            sheet(.teal)
                .rotation3DEffect(.degrees(style == .cube ? (1 - progress) * 90 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.4)
                .offset(x: style == .fade ? (1 - progress) * 8 : (1 - progress) * 48)
                .opacity(style == .fade ? progress : 1)
            sheet(.accentColor)
                .rotation3DEffect(.degrees(style == .cube ? -progress * 90 : 0), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.4)
                .offset(x: style == .fade ? -progress * 8 : -progress * 48)
                .opacity(style == .fade ? 1 - progress : progress >= 0.999 ? 0 : 1)
        }.frame(maxWidth: .infinity).frame(height: 84).clipped().accessibilityHidden(true)
            .task(id: "\(selected)-\(reduceMotion)") {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { progress = selected && !reduceMotion ? 0 : 0.3 }
                guard selected, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.05)) { progress = 1 }
            }
    }
}
