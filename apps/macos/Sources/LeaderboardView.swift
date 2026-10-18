import SwiftUI
import CoreText
import LeaderboardCore

/// Screenshot toast state. `@State` is a SwiftUI macro, and Command Line Tools
/// do not ship the SwiftUIMacros plugin, so this stays an observable object.
@MainActor
private final class ScreenshotUIState: ObservableObject {
    @Published var note: String?
    @Published var noteID = 0
    @Published var isCapturing = false
    @Published var licenseSection: LicenseSection?
    @Published var showOfficialAccounts = false
}

private enum DesktopBrandInkTop: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.top] }
}
private enum DesktopBrandInkBottom: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.bottom] }
}
private extension VerticalAlignment {
    static let desktopBrandInkTop = VerticalAlignment(DesktopBrandInkTop.self)
    static let desktopBrandInkBottom = VerticalAlignment(DesktopBrandInkBottom.self)
}

private struct DesktopBrandHeadingLayout: Layout {
    private func measurements(_ subviews: Subviews, width: CGFloat? = nil) -> ([ViewDimensions], [CGPoint], CGSize) {
        var dimensions = subviews.map { $0.dimensions(in: .unspecified) }
        if let width {
            dimensions[1] = subviews[1].dimensions(in: ProposedViewSize(
                width: max(1, width - dimensions[0].width - 6), height: nil))
        }
        let span = dimensions[0][.desktopBrandInkBottom] - dimensions[0][.desktopBrandInkTop]
        let x = dimensions[0].width + 6
        let subtitleCenter = span / 2
        var origins = [CGPoint(x: 0, y: -dimensions[0][.desktopBrandInkTop]),
                       CGPoint(x: x, y: subtitleCenter - dimensions[1].height / 2)]
        let top = origins.map(\.y).min() ?? 0
        for index in origins.indices { origins[index].y -= top }
        let height = zip(dimensions, origins).map { $0.0.height + $0.1.y }.max() ?? 0
        return (dimensions, origins, CGSize(width: x + dimensions[1].width, height: height))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measurements(subviews, width: proposal.width).2
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (dimensions, origins, _) = measurements(subviews, width: bounds.width)
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + origins[index].x, y: bounds.minY + origins[index].y),
                anchor: .topLeading, proposal: ProposedViewSize(width: dimensions[index].width, height: dimensions[index].height))
        }
    }
}

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    @StateObject private var screenshot = ScreenshotUIState()

    private var language: AppLanguage { state.selectedLanguage }
    private func tr(_ english: String, _ chinese: String) -> String {
        language.text(english, chinese)
    }

    private static let minimumWidth: CGFloat = 850
    // macOS Table adds its own padding around fixed-width columns.
    // Nine native columns: the two added columns also get AppKit cell insets.
    private static let rankColumnWidth: CGFloat = 36
    private static let tableChromeBaseWidth: CGFloat = 308
    // Reduce the panel by the same amount as its fixed columns, preserving
    // the name space required by every category and company purchase links.
    private static let preferredTableChromeWidth: CGFloat = 524
    private static let countryColumnWidth: CGFloat = 32
    private static let opennessColumnWidth: CGFloat = 32
    /// Row height SwiftUI settles on for these cells. The panel height has to
    /// preserve the existing viewport; additional rows scroll inside it.
    private static let tableRowHeight: CGFloat = 32
    /// `.tableStyle(.bordered)` insets the clip view by 1pt top and bottom, so
    /// the rows need 2pt more than the table frame hands them.
    private static let tableBorderHeight: CGFloat = 2

    let maximumWidth: CGFloat
    var viewportSize: CGSize? = nil

    private var contentWidth: CGFloat {
        viewportSize?.width ?? Self.preferredWidth(for: state, maximumWidth: maximumWidth)
    }

    private var contentHeight: CGFloat {
        viewportSize?.height ?? Self.preferredHeight(for: state, width: contentWidth, maximumWidth: maximumWidth)
    }

    private var nameColumnWidth: CGFloat {
        (contentWidth - Self.tableChromeWidth) / 2
    }

    private static var tableChromeWidth: CGFloat {
        tableChromeBaseWidth + (countryColumnWidth + opennessColumnWidth) * 2
    }

    static func preferredWidth(for state: AppState, maximumWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let captionFont = NSFont.systemFont(ofSize: 12)
        // Size against every category and grouping. Switching tabs then keeps
        // the popover width stable even when the video rows have short names.
        let columnWidth = LeaderboardCategory.allCases.flatMap { category in
            LeaderboardGrouping.allCases.map { grouping in
                category.boardKinds
                    .flatMap { kind -> [LeaderboardEntry] in
                        LeaderboardPresentation.rows(state.snapshot.boards[kind], grouping: grouping)
                    }
                    .map { entry -> CGFloat in
                        let nameWidth = (entry.name as NSString).size(withAttributes: [.font: font]).width
                        var width = nameWidth + 54 // Logo, spacing, cell padding, and table inset.
                        if grouping == .company {
                            let links = PurchaseLinkCatalog.links(
                                forOrganization: entry.organization,
                                modelName: entry.name
                            )
                            let titles = [
                                (links.codingPlan, state.selectedLanguage.text("Plan", "套餐")),
                                (links.payAsYouGo, state.selectedLanguage.text("Pay as you go", "按量")),
                            ].compactMap { item in item.0.isEmpty ? nil : item.1 }
                            if !titles.isEmpty {
                                width += 10 + CGFloat(titles.count - 1) * 10
                                width += titles.reduce(0) { partial, title in
                                    partial + (title as NSString).size(withAttributes: [.font: captionFont]).width + 4
                                }
                            }
                        }
                        return width
                    }
                    .max() ?? 0
            }
        }.max() ?? 0
        let headerWidth = LeaderboardCategory.allCases.flatMap { category -> [CGFloat] in
            let lenses = category.sourceLenses(language: state.selectedLanguage)
            return [
                SourceTableHeaderView.requiredNameColumnWidth(
                    title: boardColumnTitle(category.leftColumnTitle, kind: category.leftKind, state: state),
                    summary: lenses.aa
                ),
                SourceTableHeaderView.requiredNameColumnWidth(
                    title: boardColumnTitle(category.rightColumnTitle, kind: category.rightKind, state: state),
                    summary: lenses.arena
                ),
            ]
        }.max() ?? 0
        let desired = max(minimumWidth, ceil(max(columnWidth, headerWidth) * 2 + preferredTableChromeWidth))
        return min(desired, maximumWidth)
    }

    static func preferredSize(for state: AppState, maximumWidth: CGFloat) -> NSSize {
        let width = preferredWidth(for: state, maximumWidth: maximumWidth)
        return NSSize(width: width, height: preferredHeight(for: state, width: width, maximumWidth: maximumWidth))
    }

    static func preferredHeight(for state: AppState, width: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        let view = LeaderboardView(state: state, maximumWidth: maximumWidth)
        let header = NSHostingView(rootView: view.header.frame(width: width))
        let footer = NSHostingView(rootView: view.footer.frame(width: width))
        // Native header plus visible rows plus the bordered style's insets.
        // Country and source filters can shorten the table.
        return ceil(header.fittingSize.height + SourceTableHeaderView.height
            + CGFloat(visibleRowCount(for: state)) * tableRowHeight
            + tableBorderHeight + 1 + footer.fittingSize.height)
    }

    private static func visibleRowCount(for state: AppState) -> Int {
        let kinds = state.selectedCategory.boardKinds
        let raw = kinds.map { state.snapshot.boards[$0]?.entries ?? [] }
        if raw.allSatisfy(\.isEmpty) || kinds.allSatisfy({ state.countryFilters[$0] == nil && state.opennessFilters[$0] == nil }) {
            return 20
        }
        let counts = kinds.map { kind in
            LeaderboardPresentation.rows(state.snapshot.boards[kind], grouping: state.selectedGrouping,
                filter: state.countryFilters[kind] ?? .all, openness: state.opennessFilters[kind] ?? .all).count
        }
        return min(20, max(1, counts.max() ?? 0))
    }

    private static func boardColumnTitle(
        _ title: String,
        kind: LeaderboardKind,
        state: AppState
    ) -> String {
        LeaderboardPresentation.explanation(kind, language: state.selectedLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Divider()
            footer
        }
        .frame(width: contentWidth, height: contentHeight)
        .background(BrandTheme.background(for: colorScheme))
        .tint(BrandTheme.accent(for: colorScheme))
        .accentColor(BrandTheme.accent(for: colorScheme))
        .sheet(item: $screenshot.licenseSection) { section in
            LicenseNoticesView(section: section, language: language)
        }
        .sheet(isPresented: $screenshot.showOfficialAccounts) {
            OfficialQuotaAccountsView(state: state, onClose: { screenshot.showOfficialAccounts = false })
        }
        .overlay(alignment: .bottom) {
            if let note = screenshot.note, !state.isQuitting {
                screenshotToast(note)
            }
        }
        .overlay {
            if state.isQuitting {
                quittingOverlay
            }
        }
    }

    /// Painted before terminate. Closing this popover tears down the table on
    /// the main thread, so the click itself has to show feedback first.
    private var quittingOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(tr("Quitting…", "正在退出…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
    }

    private var header: some View {
        // Keep the quota row's frame so screenshots can replace it with the
        // same CC Switch guide shown when quotas are unavailable.
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            if !state.quotaChips.isEmpty {
                QuotaStrip(
                    chips: state.quotaChips,
                    language: language,
                    onConnectQwen: state.connectQwenWebsite,
                    onConnectOpenAI: state.connectOpenAI,
                    onConnectXAI: state.connectXAI,
                    onRecoverGLM: state.recoverGLMQuota,
                    onAddModel: { screenshot.showOfficialAccounts = true },
                    connectingOpenAIProviderID: state.connectingOpenAIProviderID
                )
                .padding(.top, 10)
                .background(QuotaStripAnchor())
            } else {
                HStack(spacing: 6) {
                    if state.ccSwitchEmptyState != nil { quotaSetupPrompt }
                    AddModelButton(language: language) { screenshot.showOfficialAccounts = true }
                }
                .padding(.top, 10)
                .background(QuotaStripAnchor())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var quotaSetupPrompt: some View {
        quotaSetupPrompt(isScreenshot: false)
    }

    private func quotaSetupPrompt(isScreenshot: Bool) -> some View {
        let installed = !isScreenshot && state.ccSwitchEmptyState == .installedEmpty
        return HStack(spacing: 3) {
            Text(installed ? tr("Open", "请在") : tr("Install", "安装"))
                .foregroundStyle(.secondary)
            if isScreenshot {
                // ImageRenderer cannot draw AppKit-backed Link controls.
                Text("CC Switch")
                    .underline()
                    .foregroundStyle(BrandTheme.accent(for: colorScheme))
            } else if installed {
                Button(action: state.openCCSwitch) {
                    Text("CC Switch").underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandTheme.accent(for: colorScheme))
                .pointingHandCursor()
            } else {
                Link(destination: CCSwitchProviderStore.downloadURL) {
                    Text("CC Switch").underline().foregroundColor(BrandTheme.accent(for: colorScheme))
                }
                .pointingHandCursor()
            }
            Text(installed
                 ? tr("to add a provider or sign in and see quotas here.", "中添加供应商或登录，即可在这里查看余量。")
                 : tr("to see provider quotas here.", "，即可在这里查看各家提供商的余量。"))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("quota-setup-placeholder")
    }

    @ViewBuilder
    private var titleRow: some View {
        if contentWidth < (language == .english ? 1300 : 1100) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    appTitle
                    Spacer(minLength: 12)
                    freshness
                }
                HStack(spacing: 8) {
                    groupingPicker
                    categoryPicker
                    comparisonPicker
                }
            }
        } else {
            // Equal side columns keep the tabs centered on wider panels.
            HStack(alignment: .center, spacing: 12) {
                appTitle.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    groupingPicker
                    categoryPicker
                    comparisonPicker
                }
                freshness.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var appTitle: some View {
        let title = language.appName
        let english = language == .english
        return DesktopBrandHeadingLayout {
            Group {
                if english {
                    EnglishBrandTitle(fontSize: 21)
                } else {
                    ChineseBrandTitle()
                }
            }
            .alignmentGuide(.desktopBrandInkTop) { dimensions in
                english ? Self.textInkEdge(dimensions, text: title,
                    font: NSFont(name: "SnellRoundhand-Bold", size: 21)!, top: true)
                    : dimensions.height - dimensions[.bottom]
            }
            .alignmentGuide(.desktopBrandInkBottom) { dimensions in
                english ? Self.textInkEdge(dimensions, text: title,
                    font: NSFont(name: "SnellRoundhand-Bold", size: 21)!, top: false)
                    : dimensions[.bottom]
            }
            .accessibilityIdentifier("brand-title")
            Button { QuotaTrackingHelpAlert.make(language: language).runModal() } label: {
                FeatureSubtitle(language: language, height: BrandTitleMetrics.inkHeight(language: language))
                    .foregroundStyle(.secondary)
            }.buttonStyle(.plain)
                .help(AppFeatureCopy.quotaHelpLabel(language: language))
                .accessibilityLabel(AppFeatureCopy.subtitle(language: language))
                .accessibilityIdentifier("brand-subtitle")
            .alignmentGuide(.desktopBrandInkBottom) { dimensions in
                dimensions.height
            }
        }
    }

    nonisolated private static func textInkEdge(_ dimensions: ViewDimensions, text: String, font: NSFont, top: Bool) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attributed), .useGlyphPathBounds)
        guard !ink.isNull, !ink.isEmpty else { return dimensions[top ? .top : .bottom] }
        return dimensions[.firstTextBaseline] - (top ? ink.maxY : ink.minY)
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            freshnessLine(now: context.date)
        }
    }

    private var groupingPicker: some View {
        GroupingSegmentedControl(
            language: language,
            selection: Binding(
                get: { state.selectedGrouping },
                set: { state.selectGrouping($0) }
            )
        )
        .frame(width: GroupingSegmentedControl.width, height: GroupingSegmentedControl.height)
        .help(tr("Company scores use each company's strongest model.", "按公司查看时，以最强模型分数为准，弱型号不拉低"))
    }

    @ViewBuilder private var comparisonPicker: some View {
        if selectedCategory == .general {
            Picker(tr("Compare with", "对照来源"), selection: $state.generalComparison) {
                Text("Arena").tag(LeaderboardKind.arenaText)
                Text("Epoch ECI").tag(LeaderboardKind.epochECI)
            }.labelsHidden().frame(width: 112)
                .accessibilityIdentifier("general-comparison-source")
                .help(tr("Choose the second general leaderboard", "选择综合榜的第二个对照来源"))
        }
    }

    private var categoryPicker: some View {
        CategorySegmentedControl(
            language: language,
            selection: Binding(
                get: { state.selectedCategory },
                set: { state.selectCategory($0) }
            )
        )
        .frame(width: CategorySegmentedControl.width, height: CategorySegmentedControl.height)
        .help(tr("Switch leaderboard category", "切换榜单类别"))
    }

    private var rightKind: LeaderboardKind { selectedCategory == .general ? state.generalComparison : selectedCategory.rightKind }
    private var rightColumnTitle: String { LeaderboardPresentation.title(rightKind, language: language) }

    private var selectedCategory: LeaderboardCategory {
        state.selectedCategory
    }

    /// One heading identifies both timestamps; each value sits in its own pill
    /// so the ranking data and this Mac's quota data stay distinguishable.
    private func freshnessLine(now: Date) -> some View {
        HStack(spacing: 8) {
            Text(tr("UPDATED", "更新时间"))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            // Shrinking would break the equal-width guarantee, so both values
            // keep their natural size.
            freshnessPill(rankingClause(now: now, format: .relative), failed: rankingFailed)
            if let quota = quotaClause(now: now, format: .relative) {
                freshnessPill(quota, failed: state.quotaUnavailable)
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(freshnessAccessibilityLabel(now: now))
        .help(freshnessHelp(now: now))
    }

    /// The copy stays relative because that is what reads at a glance, but
    /// `刚刚` and `23 分钟前` differ by ~28pt, and in a right-aligned row that
    /// width would shove the heading sideways every minute. A fixed-width pill
    /// absorbs the difference as its own padding, so the heading never moves
    /// and no hole opens in the header. The slot fits the longest template per
    /// language (`榜单 59 分钟前` / `Rankings 59 min ago`) plus the padding.
    private func freshnessPill(_ text: String, failed: Bool) -> some View {
        Text(text)
            .foregroundStyle(failed ? Color.orange : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            // Left-aligned so `榜单` / `Rankings` stay pinned too; the width
            // difference then lands in the pill's trailing padding.
            .frame(width: language == .english ? 124 : 92, alignment: .leading)
            .background(
                Capsule().fill(failed ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.10))
            )
    }

    /// How a timestamp is spelled. The panel shows `.relative` because age is
    /// what matters at a glance; the tooltip and VoiceOver use `.both` so the
    /// exact clock time stays one hover away.
    private enum FreshnessFormat {
        case stamp
        case relative
        /// Tooltip form: the clock time plus the relative age, so a panel that
        /// only shows `HH:mm` never has to be converted by hand.
        case both
    }

    private func freshnessValue(_ date: Date, now: Date, format: FreshnessFormat) -> String {
        switch format {
        case .stamp: clockStamp(date, now: now)
        case .relative: LeaderboardPresentation.updateAge(date, language: language, now: now)
        case .both: stampWithAge(date, now: now)
        }
    }

    private func stampWithAge(_ date: Date, now: Date) -> String {
        let age = LeaderboardPresentation.updateAge(date, language: language, now: now)
        return clockStamp(date, now: now) + tr(" (\(age))", "（\(age)）")
    }

    /// Same-day data shows the clock time; an older fetch adds the date so a
    /// stale panel cannot read as today's. Matches `resetClock` and the board
    /// column titles.
    private func clockStamp(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: now)
            ? "HH:mm"
            : "M/d HH:mm"
        return formatter.string(from: date)
    }

    private func rankingClause(now: Date, format: FreshnessFormat) -> String {
        // Use the oldest visible board so a partially refreshed category does
        // not appear newer than all of its data.
        let fetchedAt = state.selectedCategory.boardKinds
            .compactMap { state.snapshot.boards[$0]?.fetchedAt }
            .min()
        // Keep the space so the value column lines up with `榜单 23 分钟前`.
        guard let fetchedAt else { return tr("Rankings pending", "榜单 待更新") }
        let value = freshnessValue(fetchedAt, now: now, format: format)
        return tr("Rankings \(value)", "榜单 \(value)")
    }

    private var rankingFailed: Bool {
        !state.isRefreshing && !state.lastErrors.isEmpty
    }

    private func freshnessSummary(now: Date) -> String {
        var summary = tr("Last updated: ", "更新时间：")
            + rankingClause(now: now, format: .both)
        if let quota = quotaClause(now: now, format: .both) {
            summary += tr("; ", "；") + quota
        }
        return summary
    }

    private func freshnessAccessibilityLabel(now: Date) -> String {
        var label = freshnessSummary(now: now)
        if state.isRefreshing {
            label = tr("Updating rankings. \(label)", "正在更新排名。\(label)")
        } else if rankingFailed {
            label = tr("Some rankings failed to update. \(label)", "部分排名更新失败。\(label)")
        }
        return label
    }

    private func freshnessHelp(now: Date) -> String {
        var parts: [String] = []
        if state.isRefreshing {
            parts.append(tr("Updating rankings", "正在更新排名"))
        } else if !state.lastErrors.isEmpty {
            parts.append(tr("Some rankings failed to update", "部分排名更新失败"))
        }
        parts.append(freshnessSummary(now: now))
        if state.quotaUnavailable && state.quotaChips.isEmpty {
            parts.append(tr("Quota unavailable; CC Switch database could not be read", "余量暂不可读，这次没读成本机 CC Switch 数据库"))
        } else if state.quotaUnavailable {
            parts.append(tr("Quota refresh failed; showing previous values", "余量数据库这次没有读成，显示的是上次余量"))
        } else if quotaClause(now: now, format: .relative) != nil {
            parts.append(tr("Quota comes from this Mac's CC Switch data", "余量来自本机 CC Switch。没安装或读不懂配置时不显示，也不需要安装 Codex"))
        }
        return parts.joined(separator: tr(". ", "。"))
    }

    private func quotaClause(now: Date, format: FreshnessFormat) -> String? {
        if state.quotaChips.isEmpty {
            return state.quotaUnavailable ? tr("Quota unavailable", "余量 暂不可读") : nil
        }
        guard let updatedAt = state.quotaUpdatedAt else { return tr("Quota pending", "余量 待更新") }
        let value = freshnessValue(updatedAt, now: now, format: format)
        return tr("Quota \(value)", "余量 \(value)")
    }

    // Both name columns grow with the longest visible name. The country and
    // score columns stay aligned across rows and both halves of the table.
    private var table: some View {
        let lenses = (aa: SourceLensDescription(emphasis: LeaderboardPresentation.explanation(selectedCategory.leftKind, language: language)),
                      arena: SourceLensDescription(emphasis: LeaderboardPresentation.explanation(rightKind, language: language)))
        return Table(rows) {
            TableColumn(tr("Rank", "排名")) { row in
                Text(LeaderboardPresentation.rankLabel(row.rank))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(Self.rankColumnWidth)
            .alignment(.center)

            TableColumn(Self.boardColumnTitle(
                selectedCategory.leftColumnTitle,
                kind: selectedCategory.leftKind,
                state: state
            )) { row in
                LeaderboardCell(model: row.left, language: language, onCopyName: nameCopyAction)
            }
            .width(nameColumnWidth)

            TableColumn(tr("Country", "国家")) { row in
                CountryCell(model: row.left, language: language)
            }
            .width(Self.countryColumnWidth)
            .alignment(.center)

            TableColumn(ModelOpenness.columnTitle(language: language)) { row in
                OpennessCell(model: row.left, language: language)
            }
            .width(Self.opennessColumnWidth)
            .alignment(.center)

            TableColumn(tr("Score", "分数")) { row in
                ScoreCell(model: row.left, scoreDigits: 1, shareColor: .blue)
            }
            .width(60)
            .alignment(.center)

            TableColumn(Self.boardColumnTitle(
                rightColumnTitle,
                kind: rightKind,
                state: state
            )) { row in
                LeaderboardCell(model: row.right, language: language, onCopyName: nameCopyAction)
            }
            .width(nameColumnWidth)

            TableColumn(tr("Country", "国家")) { row in
                CountryCell(model: row.right, language: language)
            }
            .width(Self.countryColumnWidth)
            .alignment(.center)

            TableColumn(ModelOpenness.columnTitle(language: language)) { row in
                OpennessCell(model: row.right, language: language)
            }
            .width(Self.opennessColumnWidth)
            .alignment(.center)

            TableColumn(tr("Score", "分数")) { row in
                ScoreCell(model: row.right, scoreDigits: rightKind == .epochECI ? 2 : 1, shareColor: .purple)
            }
            .width(60)
            .alignment(.center)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .scrollIndicators(.automatic)
        .overlay(TableChrome(
            left: lenses.aa,
            right: lenses.arena,
            leftHelp: selectedCategory.leftColumnTitle + tr(". ", "。")
                + LeaderboardPresentation.sourceHelp(selectedCategory.leftKind, language: language,
                    board: state.snapshot.boards[selectedCategory.leftKind], includesFetchTime: false),
            rightHelp: rightColumnTitle + tr(". ", "。")
                + LeaderboardPresentation.sourceHelp(rightKind, language: language,
                    board: state.snapshot.boards[rightKind], includesFetchTime: false),
            leftKind: selectedCategory.leftKind,
            rightKind: rightKind,
            language: language,
            leftFilter: state.countryFilters[selectedCategory.leftKind] ?? .all,
            rightFilter: state.countryFilters[rightKind] ?? .all,
            leftCountryOptions: countryOptions(for: selectedCategory.leftKind),
            rightCountryOptions: countryOptions(for: rightKind),
            leftOpenness: state.opennessFilters[selectedCategory.leftKind] ?? .all,
            rightOpenness: state.opennessFilters[rightKind] ?? .all,
            onOpennessFilter: { kind, filter in state.selectOpennessFilter(filter, for: kind) },
            onCountryFilter: { kind, filter in
                state.selectCountryFilter(filter, for: kind)
            },
            showsSkeleton: needsSkeleton
        ))
        .id(contentWidth)
        .redacted(reason: needsSkeleton ? .placeholder : [])
        .disabled(needsSkeleton)
    }

    private func sourceLink(title: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
            }
        }
        .buttonStyle(.link)
        .pointingHandCursor()
        .help(url)
    }

    private let repositoryURL = "https://github.com/cloydlau/ai-benchgauge"

    private func quit() {
        guard state.beginQuitting() else { return }
        Task { @MainActor in
            // One frame is not always enough for SwiftUI to commit the overlay
            // before terminate freezes the window on the main thread.
            try? await Task.sleep(for: .milliseconds(120))
            NSApp.terminate(nil)
        }
    }

    /// Wait out the button highlight, then copy. The balance row stays visible
    /// in the app; only the copied image shows the CC Switch guide instead.
    private func captureScreenshot() {
        guard !state.isQuitting, !screenshot.isCapturing else { return }
        screenshot.isCapturing = true
        let settle = screenshot.note == nil ? 120 : 240
        screenshot.noteID += 1
        screenshot.note = nil
        Task { @MainActor in
            defer { screenshot.isCapturing = false }
            try? await Task.sleep(for: .milliseconds(settle))
            performScreenshotCapture()
        }
    }

    private func performScreenshotCapture() {
        guard !state.isQuitting else { return }
        guard let view = panelContentView() else {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        // A panel flush with the screen edge clips its top-right corner, and
        // that clipped region is blank in the bitmap.
        keepPanelInsideScreen(view)
        view.layoutSubtreeIfNeeded()
        let band = state.quotaChips.isEmpty ? nil : PanelScreenshot.quotaStripBand(in: view)
        // Do not copy balances in the clear if the row could not be found.
        if !state.quotaChips.isEmpty, band == nil {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        var replacement: (band: CGRect, prompt: CGImage)?
        if let band {
            let content = quotaSetupPrompt(isScreenshot: true)
                .padding(.horizontal, 18)
                .frame(width: band.width, height: band.height)
                .environment(\.colorScheme, colorScheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = view.window?.backingScaleFactor ?? 2
            guard let prompt = renderer.cgImage else {
                showScreenshotNote(tr("Screenshot failed", "截图失败"))
                return
            }
            replacement = (band, prompt)
        }
        guard let footerBand = PanelScreenshot.footerBand(in: view) else {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        let footerRenderer = ImageRenderer(content: screenshotFooter
            .frame(width: footerBand.width, height: footerBand.height)
            .environment(\.colorScheme, colorScheme))
        footerRenderer.scale = view.window?.backingScaleFactor ?? 2
        guard let footerImage = footerRenderer.cgImage,
              let shot = PanelScreenshot.capture(view: view, replacingTopBandWith: replacement,
                                                 replacingFooterBandWith: (footerBand, footerImage)) else {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        if band != nil, !shot.replacedBand {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        guard PanelScreenshot.copyToPasteboard(image: shot.image, png: shot.png) else {
            showScreenshotNote(tr("Screenshot failed", "截图失败"))
            return
        }
        showScreenshotNote(tr("Copied to clipboard", "已复制到剪贴板"))
    }

    /// Placeholder rows are not real names. A click there must not copy them.
    private var nameCopyAction: ((String) -> Bool)? {
        guard !needsSkeleton else { return nil }
        return { name in
            copyDisplayedName(name)
        }
    }

    /// Copies the text in the name column. Company mode copies the company
    /// name, because that is what the column shows.
    @discardableResult
    private func copyDisplayedName(_ name: String) -> Bool {
        guard !name.isEmpty, !screenshot.isCapturing, !state.isQuitting else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(name, forType: .string) else {
            showScreenshotNote(tr("Copy failed", "复制失败"))
            return false
        }
        showScreenshotNote(tr("Copied ", "已复制 ") + name)
        return true
    }

    private func showScreenshotNote(_ text: String) {
        screenshot.noteID += 1
        let noteID = screenshot.noteID
        withAnimation(.easeOut(duration: 0.15)) {
            screenshot.note = text
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard screenshot.noteID == noteID, !state.isQuitting else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                screenshot.note = nil
            }
        }
    }

    private func keepPanelInsideScreen(_ view: NSView) {
        guard viewportSize == nil else { return }
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        let margin: CGFloat = 8
        guard frame.width <= visible.width - margin * 2 else { return }
        if frame.maxX > visible.maxX - margin {
            frame.origin.x -= frame.maxX - (visible.maxX - margin)
        }
        if frame.minX < visible.minX + margin {
            frame.origin.x = visible.minX + margin
        }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
        view.layoutSubtreeIfNeeded()
    }

    private func panelContentView() -> NSView? {
        if viewportSize != nil,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue == "ai-benchgauge.leaderboard-window" }) {
            return window.contentViewController?.view
        }
        let ordered = NSApp.windows.filter(\.isVisible) + NSApp.windows.filter { !$0.isVisible }
        for window in ordered {
            if let view = window.contentViewController?.view as? NSHostingView<LeaderboardView> {
                return view
            }
        }
        for window in ordered {
            guard let view = window.contentViewController?.view else { continue }
            if abs(view.bounds.width - contentWidth) < 2,
               abs(view.bounds.height - contentHeight) < 2 {
                return view
            }
        }
        return nil
    }

    private func screenshotToast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 480)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .padding(.bottom, 48)
            .allowsHitTesting(false)
            .accessibilityLabel(message)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(compact: false, showsSourceLinks: true)
            footerRow(compact: false, showsSourceLinks: false)
            footerRow(compact: true, showsSourceLinks: false)
            footerRow(compact: true, showsSourceLinks: false, stacked: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(ScreenshotFooterAnchor())
        .accessibilityIdentifier("leaderboard-footer")
    }

    /// A shared image needs a readable project address in place of controls.
    /// Keep the same single-row footer and canvas size as the live panel.
    private var screenshotFooter: some View {
        ViewThatFits(in: .horizontal) {
            screenshotFooterRow(showsSources: true)
            screenshotFooterRow(showsSources: false)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
    }

    private func screenshotFooterRow(showsSources: Bool) -> some View {
        HStack(spacing: 7) {
            githubMark
            Text(repositoryURL.replacingOccurrences(of: "https://", with: ""))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                if showsSources {
                    Text(selectedCategory.leftKind.sourceLinkTitle)
                    Text("·")
                    Text(rightKind.sourceLinkTitle)
                    Text("·")
                }
                Text("Cloyd Lau · MIT License")
            }
            .fixedSize()
        }
    }

    private func footerRow(compact: Bool, showsSourceLinks: Bool, stacked: Bool = false) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: compact ? 4 : 7))
        return layout {
            HStack(spacing: compact ? 4 : 7) {
                footerAttribution(compact: compact)
                Text("·")
                Button(tr(compact ? "Notices" : "Open-source notices", "开源声明")) {
                    screenshot.licenseSection = .thirdParty
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(tr("View third-party licenses and copyright notices", "查看第三方许可证和版权声明"))
                .accessibilityLabel(tr("Open-source notices", "开源声明"))
                .accessibilityIdentifier("open-source-notices")
                .fixedSize()
            }
            if !stacked { Spacer(minLength: 8) }
            HStack(spacing: compact ? 4 : 7) {
                if showsSourceLinks {
                    footerSources
                } else {
                    Menu(tr("Sources", "数据来源")) {
                        sourceLink(title: selectedCategory.leftKind.sourceLinkTitle,
                                   url: selectedCategory.leftKind.sourceURL.absoluteString)
                        sourceLink(title: rightKind.sourceLinkTitle,
                                   url: rightKind.sourceURL.absoluteString)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(tr("Leaderboard data sources", "榜单数据来源"))
                }
                Text("·")
                footerControls(compact: compact)
            }
        }
    }

    private func footerAttribution(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 7) {
            Button {
                if let url = URL(string: repositoryURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                githubMark
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(repositoryURL)

            Text("Cloyd Lau")
            Text("·")
            Button(compact ? "MIT" : "MIT License") {
                screenshot.licenseSection = .application
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(tr("View the AI BenchGauge license", "查看 AI 天梯的许可证"))
            .accessibilityIdentifier("application-license")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var footerSources: some View {
        HStack(spacing: 7) {
            Text(tr("Sources", "数据来源"))
            sourceLink(
                title: selectedCategory.leftKind.sourceLinkTitle,
                url: selectedCategory.leftKind.sourceURL.absoluteString
            )
            Text("·")
            sourceLink(
                title: rightKind.sourceLinkTitle,
                url: rightKind.sourceURL.absoluteString
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func footerControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 7) {
            Toggle(tr("Codex task counts", "Codex 任务统计"), isOn: Binding(
                get: { state.showsCodexTaskStatus },
                set: { state.setShowsCodexTaskStatus($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .help(tr("Show running, unread and failed Codex task counts in the menu bar", "在菜单栏显示 Codex 运行中、待查看和报错的任务数量"))
            .accessibilityLabel(tr("Show Codex task counts in the menu bar", "在菜单栏显示 Codex 任务统计"))
            .accessibilityIdentifier("codex-task-status-toggle")

            Text("·")

            Button {
                captureScreenshot()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .imageScale(.small)
                    if !compact { Text(tr("Screenshot", "截图")) }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor(isEnabled: !state.isQuitting && !screenshot.isCapturing)
            .allowsHitTesting(!state.isQuitting && !screenshot.isCapturing)
            .help(tr("Copy a screenshot with the CC Switch quota guide", "复制显示 CC Switch 余量引导的截图"))
            .accessibilityLabel(tr("Screenshot", "截图"))
            .accessibilityIdentifier("copy-panel-screenshot")

            Text("·")

            PanelModePicker(language: language, selection: Binding(
                get: { state.panelMode },
                set: { state.selectPanelMode($0) }
            ))
            .fixedSize()

            Text("·")

            Picker(tr("Language", "语言"), selection: Binding(
                get: { state.selectedLanguage },
                set: { state.selectLanguage($0) }
            )) {
                Text("EN").tag(AppLanguage.english)
                Text("简中").tag(AppLanguage.chinese)
                Text("繁中").tag(AppLanguage.traditionalChinese)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: compact ? 120 : 150)
            .help(tr("Interface language", "界面语言"))

            Text("·")

            Button {
                quit()
            } label: {
                HStack(spacing: 4) {
                    if state.isQuitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                        if !compact { Text(tr("Quitting", "退出中")) }
                    } else {
                        Image(systemName: "power")
                            .imageScale(.small)
                        if !compact { Text(tr("Quit", "退出")) }
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor(isEnabled: !state.isQuitting)
            .allowsHitTesting(!state.isQuitting)
            .help(state.isQuitting ? tr("Quitting AI BenchGauge", "正在退出 AI 天梯") : tr("Quit AI BenchGauge", "退出 AI 天梯"))
            .accessibilityLabel(tr("Quit", "退出"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder
    private var githubMark: some View {
        if let mark = Self.bundledGitHubMark {
            Image(nsImage: mark)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
        } else {
            Image(systemName: "link")
                .imageScale(.small)
        }
    }

    private static let bundledGitHubMark: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appending(path: "logos/github.png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Empty boards skeleton from the raw model list, not the company
    /// aggregation. Grouping is a local view and must not look like a fetch.
    private var needsSkeleton: Bool {
        let leftEmpty = state.snapshot.boards[selectedCategory.leftKind]?.entries.isEmpty ?? true
        let rightEmpty = state.snapshot.boards[rightKind]?.entries.isEmpty ?? true
        return leftEmpty && rightEmpty
    }

    private var rows: [LeaderboardRow] {
        if needsSkeleton {
            return (0..<Self.visibleRowCount(for: state)).map { index in
                LeaderboardRow(
                    rank: index + 1,
                    left: .placeholder(rank: index + 1),
                    right: .placeholder(rank: index + 1)
                )
            }
        }

        let left = displayedEntries(kind: selectedCategory.leftKind)
        let right = displayedEntries(kind: rightKind)
        let organizationLogos = self.organizationLogos

        return (0..<max(Self.visibleRowCount(for: state), left.count, right.count)).map { index in
            LeaderboardRow(
                rank: index + 1,
                left: cellModel(
                    for: index < left.count ? left[index] : nil,
                    organizationLogos: organizationLogos, leaderScore: left.first?.entry.score
                ),
                right: cellModel(
                    for: index < right.count ? right[index] : nil,
                    organizationLogos: organizationLogos, leaderScore: rightKind == .epochECI ? nil : right.first?.entry.score
                )
            )
        }
    }

    /// Company rows are derived here, from models already on the board.
    /// Short company lists keep the existing dash slots; longer lists scroll.
    private func displayedEntries(kind: LeaderboardKind) -> [DisplayedLeaderboardEntry] {
        let board = state.snapshot.boards[kind]
        let filter = state.countryFilters[kind] ?? .all
        let openness = state.opennessFilters[kind] ?? .all
        guard state.selectedGrouping == .company else {
            return LeaderboardPresentation.rows(board, grouping: .model, filter: filter, openness: openness).map {
                DisplayedLeaderboardEntry(entry: $0, scoreHelp: nil, isCompany: false)
            }
        }
        return LeaderboardPresentation.companies(board, filter: filter, openness: openness).map { standing in
            DisplayedLeaderboardEntry(
                entry: standing.entry,
                scoreHelp: CompanyLeaderboard.scoreHelp(for: standing, language: language),
                isCompany: true
            )
        }
    }

    private func countryOptions(for kind: LeaderboardKind) -> [LeaderboardCountryFilter] {
        LeaderboardPresentation.countryFilters(state.snapshot.boards[kind])
    }

    private func cellModel(
        for displayed: DisplayedLeaderboardEntry?,
        organizationLogos: [String: URL], leaderScore: Double?
    ) -> LeaderboardCellModel? {
        guard let displayed else { return nil }
        let entry = displayed.entry
        let key = OrganizationLogoCatalog.resolvedKey(
            organization: entry.organization,
            modelName: entry.name
        )
        return LeaderboardCellModel(
            entry: entry,
            brandHex: OrganizationLogoCatalog.rowBrandColorHex(for: entry),
            logoURL: entry.logoURL
                ?? key.flatMap { organizationLogos[$0] }
                ?? OrganizationLogoCatalog.logoURL(
                    forOrganization: entry.organization,
                    modelName: entry.name
                ),
            scoreHelp: displayed.scoreHelp,
            isCompany: displayed.isCompany,
            leaderScore: leaderScore
        )
    }

    private var organizationLogos: [String: URL] {
        var logos: [String: URL] = [:]
        for kind in [selectedCategory.leftKind, rightKind] {
            for item in state.snapshot.boards[kind]?.organizationLogoURLs ?? [:] {
                let key = OrganizationLogoCatalog.normalizedKey(item.key)
                if !key.isEmpty {
                    logos[key] = item.value
                }
            }
            for entry in state.snapshot.boards[kind]?.entries ?? [] {
                guard let organization = entry.organization,
                      let logoURL = entry.logoURL else { continue }
                let key = OrganizationLogoCatalog.normalizedKey(organization)
                if !key.isEmpty {
                    logos[key] = logoURL
                }
            }
        }
        return logos
    }

}

/// SwiftUI's TableColumn labels only support plain text. Install a native
/// one-line header that uses the space within each board's name column for its
/// full title and source explanation, without changing table column widths.
private struct TableChrome: NSViewRepresentable {
    let left: SourceLensDescription
    let right: SourceLensDescription
    let leftHelp: String
    let rightHelp: String
    let leftKind: LeaderboardKind
    let rightKind: LeaderboardKind
    let language: AppLanguage
    let leftFilter: LeaderboardCountryFilter
    let rightFilter: LeaderboardCountryFilter
    let leftCountryOptions: [LeaderboardCountryFilter]
    let rightCountryOptions: [LeaderboardCountryFilter]
    let leftOpenness: LeaderboardOpennessFilter
    let rightOpenness: LeaderboardOpennessFilter
    let onOpennessFilter: (LeaderboardKind, LeaderboardOpennessFilter) -> Void
    let onCountryFilter: (LeaderboardKind, LeaderboardCountryFilter) -> Void
    let showsSkeleton: Bool

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.configure(
            left: left, right: right, leftHelp: leftHelp, rightHelp: rightHelp,
            leftKind: leftKind, rightKind: rightKind,
            language: language, leftFilter: leftFilter, rightFilter: rightFilter,
            leftCountryOptions: leftCountryOptions, rightCountryOptions: rightCountryOptions,
            leftOpenness: leftOpenness, rightOpenness: rightOpenness,
            onOpennessFilter: onOpennessFilter, onCountryFilter: onCountryFilter, showsSkeleton: showsSkeleton
        )
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.configure(
            left: left, right: right, leftHelp: leftHelp, rightHelp: rightHelp,
            leftKind: leftKind, rightKind: rightKind,
            language: language, leftFilter: leftFilter, rightFilter: rightFilter,
            leftCountryOptions: leftCountryOptions, rightCountryOptions: rightCountryOptions,
            leftOpenness: leftOpenness, rightOpenness: rightOpenness,
            onOpennessFilter: onOpennessFilter, onCountryFilter: onCountryFilter, showsSkeleton: showsSkeleton
        )
    }

    final class ProbeView: NSView {
        private var left = SourceLensDescription(emphasis: "")
        private var right = SourceLensDescription(emphasis: "")
        private var leftHelp = ""
        private var rightHelp = ""
        private var leftKind: LeaderboardKind?
        private var rightKind: LeaderboardKind?
        private var language = AppLanguage.english
        private var leftFilter = LeaderboardCountryFilter.all
        private var rightFilter = LeaderboardCountryFilter.all
        private var leftCountryOptions: [LeaderboardCountryFilter] = []
        private var rightCountryOptions: [LeaderboardCountryFilter] = []
        private var leftOpenness = LeaderboardOpennessFilter.all
        private var rightOpenness = LeaderboardOpennessFilter.all
        private var onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?
        private var onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?
        private var showsSkeleton = false
        private weak var rankingScrollView: NSScrollView?
        private var backToTopButton: NSButton?

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func scrollPositionChanged() {
            guard let scroll = rankingScrollView else { return }
            backToTopButton?.isHidden = scroll.contentView.bounds.minY < 32
        }

        @objc private func backToTop() {
            guard let scroll = rankingScrollView,
                  let table = Self.findTable(in: scroll.documentView), table.numberOfRows > 0 else { return }
            table.scrollRowToVisible(0)
            scroll.reflectScrolledClipView(scroll.contentView)
            scrollPositionChanged()
        }

        private func configureRankingScroll(_ scroll: NSScrollView) {
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            if rankingScrollView !== scroll {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
                backToTopButton?.removeFromSuperview()
                rankingScrollView = scroll
                scroll.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(scrollPositionChanged),
                    name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                let button = NSButton(image: NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: nil)!,
                                      target: self, action: #selector(backToTop))
                button.bezelStyle = .circular
                button.identifier = NSUserInterfaceItemIdentifier("leaderboard-back-to-top")
                button.translatesAutoresizingMaskIntoConstraints = false
                addSubview(button)
                NSLayoutConstraint.activate([
                    button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                    button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                    button.widthAnchor.constraint(equalToConstant: 30),
                    button.heightAnchor.constraint(equalToConstant: 30),
                ])
                backToTopButton = button
            }
            let title = language.text("Back to top", "返回顶部")
            backToTopButton?.toolTip = title
            backToTopButton?.setAccessibilityLabel(title)
            scrollPositionChanged()
        }

        func configure(
            left: SourceLensDescription,
            right: SourceLensDescription,
            leftHelp: String,
            rightHelp: String,
            leftKind: LeaderboardKind,
            rightKind: LeaderboardKind,
            language: AppLanguage,
            leftFilter: LeaderboardCountryFilter,
            rightFilter: LeaderboardCountryFilter,
            leftCountryOptions: [LeaderboardCountryFilter],
            rightCountryOptions: [LeaderboardCountryFilter],
            leftOpenness: LeaderboardOpennessFilter,
            rightOpenness: LeaderboardOpennessFilter,
            onOpennessFilter: @escaping (LeaderboardKind, LeaderboardOpennessFilter) -> Void,
            onCountryFilter: @escaping (LeaderboardKind, LeaderboardCountryFilter) -> Void,
            showsSkeleton: Bool
        ) {
            self.left = left
            self.right = right
            self.leftHelp = leftHelp
            self.rightHelp = rightHelp
            self.leftKind = leftKind
            self.rightKind = rightKind
            self.language = language
            self.leftFilter = leftFilter
            self.rightFilter = rightFilter
            self.leftCountryOptions = leftCountryOptions
            self.rightCountryOptions = rightCountryOptions
            self.leftOpenness = leftOpenness
            self.rightOpenness = rightOpenness
            self.onOpennessFilter = onOpennessFilter
            self.onCountryFilter = onCountryFilter
            self.showsSkeleton = showsSkeleton
            updateTable()
        }

        override func layout() {
            super.layout()
            updateTable()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTable()
            // SwiftUI may mount the NSTableView after this background probe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateTable()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateTable()
            }
        }

        private func updateTable() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let root = self.window?.contentView else { return }
                self.configureScrollViews(in: root)
            }
        }

        private func configureScrollViews(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
                if scrollView.horizontalScrollElasticity != .none {
                    scrollView.horizontalScrollElasticity = .none
                }
                if let tableView = Self.findTable(in: scrollView.documentView),
                   tableView.tableColumns.count >= 9 {
                    configureRankingScroll(scrollView)
                    configureHeader(in: tableView, scrollView: scrollView)
                }
            }
            for child in view.subviews {
                configureScrollViews(in: child)
            }
        }

        private static func findTable(in view: NSView?) -> NSTableView? {
            guard let view else { return nil }
            if let table = view as? NSTableView { return table }
            for child in view.subviews {
                if let table = findTable(in: child) { return table }
            }
            return nil
        }

        private func configureHeader(in tableView: NSTableView, scrollView: NSScrollView) {
            let header: SourceTableHeaderView
            if let existing = tableView.headerView as? SourceTableHeaderView {
                header = existing
            } else {
                header = SourceTableHeaderView(frame: NSRect(
                    x: 0, y: 0, width: tableView.bounds.width, height: SourceTableHeaderView.height
                ))
                header.tableView = tableView
                tableView.headerView = header
                scrollView.tile()
            }
            header.configure(
                left: left, right: right, language: language,
                leftKind: leftKind, rightKind: rightKind,
                leftFilter: leftFilter, rightFilter: rightFilter,
                leftCountryOptions: leftCountryOptions, rightCountryOptions: rightCountryOptions,
                leftOpenness: leftOpenness, rightOpenness: rightOpenness,
            onOpennessFilter: onOpennessFilter, onCountryFilter: onCountryFilter, showsSkeleton: showsSkeleton
            )
            tableView.tableColumns[1].headerToolTip = leftHelp
            tableView.tableColumns[5].headerToolTip = rightHelp
            let filterHelp = language.text("Filter by country", "按国家筛选")
            tableView.tableColumns[2].headerToolTip = filterHelp
            tableView.tableColumns[6].headerToolTip = filterHelp
            for index in [3, 7] { tableView.tableColumns[index].headerToolTip = language.text("Filter by source. ", "按源码筛选。") + ModelOpenness.help(language: language) }
        }
    }
}

private final class SourceTableHeaderView: NSTableHeaderView {
    static let height: CGFloat = 24
    private var left = SourceLensDescription(emphasis: "")
    private var right = SourceLensDescription(emphasis: "")
    private var language = AppLanguage.english
    private var leftKind: LeaderboardKind?
    private var rightKind: LeaderboardKind?
    private var leftFilter = LeaderboardCountryFilter.all
    private var rightFilter = LeaderboardCountryFilter.all
    private var leftCountryOptions: [LeaderboardCountryFilter] = []
    private var rightCountryOptions: [LeaderboardCountryFilter] = []
    private var leftOpenness = LeaderboardOpennessFilter.all
    private var rightOpenness = LeaderboardOpennessFilter.all
    private var onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?
    private var onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?
    private var showsSkeleton = false
    private var menuChoices: [LeaderboardCountryFilter] = []
    private var menuKind: LeaderboardKind?

    /// Body capsules are the label composited at 35/255. Header titles drawn in
    /// `labelColor` are redacted as a solid block of that color instead, so the
    /// loading bar is near-black in light mode and near-white in dark mode.
    static let placeholderAlpha: CGFloat = 35.0 / 255.0

    static func requiredNameColumnWidth(title: String, summary: SourceLensDescription) -> CGFloat {
        ceil((summary.emphasis as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ]).width + 10)
    }

    func configure(
        left: SourceLensDescription,
        right: SourceLensDescription,
        language: AppLanguage,
        leftKind: LeaderboardKind?,
        rightKind: LeaderboardKind?,
        leftFilter: LeaderboardCountryFilter,
        rightFilter: LeaderboardCountryFilter,
        leftCountryOptions: [LeaderboardCountryFilter],
        rightCountryOptions: [LeaderboardCountryFilter],
        leftOpenness: LeaderboardOpennessFilter,
        rightOpenness: LeaderboardOpennessFilter,
        onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?,
        onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?,
        showsSkeleton: Bool
    ) {
        self.left = left
        self.right = right
        self.language = language
        self.leftKind = leftKind
        self.rightKind = rightKind
        self.leftFilter = leftFilter
        self.rightFilter = rightFilter
        self.leftCountryOptions = leftCountryOptions
        self.rightCountryOptions = rightCountryOptions
        self.leftOpenness = leftOpenness
        self.rightOpenness = rightOpenness
        self.onOpennessFilter = onOpennessFilter
        self.onCountryFilter = onCountryFilter
        self.showsSkeleton = showsSkeleton
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard !showsSkeleton else { return }
        let point = convert(event.locationInWindow, from: nil)
        let column = column(at: point)
        guard [2, 3, 6, 7].contains(column) else {
            super.mouseDown(with: event)
            return
        }
        if column == 3 || column == 7 {
            guard let kind = column == 3 ? leftKind : rightKind else { return }
            menuKind = kind
            let selected = column == 3 ? leftOpenness : rightOpenness
            let menu = NSMenu()
            for (index, choice) in LeaderboardOpennessFilter.allCases.enumerated() {
                let item = NSMenuItem(title: choice.title(language: language), action: #selector(selectOpenness(_:)), keyEquivalent: "")
                item.target = self; item.tag = index; item.state = choice == selected ? .on : .off
                menu.addItem(item)
                if choice == .all { menu.addItem(.separator()) }
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        let kind = column == 2 ? leftKind : rightKind
        guard let kind else { return }
        let selected = column == 2 ? leftFilter : rightFilter
        menuChoices = column == 2 ? leftCountryOptions : rightCountryOptions
        menuKind = kind
        let menu = NSMenu()
        for (index, choice) in menuChoices.enumerated() {
            let item = NSMenuItem(
                title: choice.title(language: language),
                action: #selector(selectCountry(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = choice == selected ? .on : .off
            menu.addItem(item)
            if choice == .all && menuChoices.count > 1 {
                menu.addItem(.separator())
            }
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func selectOpenness(_ sender: NSMenuItem) {
        guard let menuKind, LeaderboardOpennessFilter.allCases.indices.contains(sender.tag) else { return }
        onOpennessFilter?(menuKind, LeaderboardOpennessFilter.allCases[sender.tag])
    }

    @objc private func selectCountry(_ sender: NSMenuItem) {
        guard let menuKind, menuChoices.indices.contains(sender.tag) else { return }
        onCountryFilter?(menuKind, menuChoices[sender.tag])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tableView, tableView.tableColumns.count >= 9 else {
            super.draw(dirtyRect)
            return
        }
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        for index in tableView.tableColumns.indices {
            let columnRect = headerRect(ofColumn: index)
            if showsSkeleton {
                switch index {
                case 1, 5:
                    drawSkeletonNameHeader(
                        tableView.tableColumns[index].headerCell.stringValue,
                        in: columnRect
                    )
                case 2, 6:
                    drawSkeletonMark(in: columnRect, width: 28)
                default:
                    // Rank and score already come back as the light placeholder.
                    tableView.tableColumns[index].headerCell.draw(withFrame: columnRect, in: self)
                }
                continue
            }
            switch index {
            case 1:
                drawBoardHeader(
                    tableView.tableColumns[index].headerCell.stringValue,
                    summary: left,
                    tint: .systemBlue,
                    in: columnRect
                )
            case 5:
                drawBoardHeader(
                    tableView.tableColumns[index].headerCell.stringValue,
                    summary: right,
                    tint: .systemPurple,
                    in: columnRect
                )
            case 3, 7:
                drawFilterHeader(title: ModelOpenness.columnTitle(language: language), active: (index == 3 ? leftOpenness : rightOpenness) != .all, in: columnRect)
            case 2, 6:
                drawCountryHeader(
                    selected: index == 2 ? leftFilter : rightFilter,
                    in: columnRect
                )
            default:
                tableView.tableColumns[index].headerCell.draw(withFrame: columnRect, in: self)
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.height - 1 : 0, width: bounds.width, height: 1).fill()
    }

    private static var placeholderColor: NSColor {
        NSColor.labelColor.withAlphaComponent(placeholderAlpha)
    }

    /// Same capsule as a redacted body name, not the opaque label block SwiftUI
    /// substitutes for this header's title run.
    private func drawSkeletonNameHeader(_ title: String, in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let measured = (title as NSString).size(withAttributes: [.font: font]).width
        let width = min(max(measured, 48), max(48, rect.width - 12))
        drawSkeletonMark(in: rect, width: width, centered: false)
    }

    private func drawSkeletonMark(in rect: NSRect, width: CGFloat, centered: Bool = true) {
        let titleRect = NSTableHeaderCell(textCell: "").titleRect(forBounds: rect)
        let height: CGFloat = 8
        let barWidth = min(width, titleRect.width)
        guard barWidth > 1, titleRect.height > 1 else { return }
        let x = centered ? titleRect.midX - barWidth / 2 : titleRect.minX
        let bar = NSRect(x: x, y: titleRect.midY - height / 2, width: barWidth, height: height)
        Self.placeholderColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2).fill()
    }

    /// The label stays on the column centre shared with the flags below, and
    /// the filter caret is stroked separately on the label's midline: an
    /// inline "⌄" rides the text baseline and reads as too low.
    private func drawCountryHeader(selected: LeaderboardCountryFilter, in rect: NSRect) {
        drawFilterHeader(title: language.text("Country", "国家"), active: selected != .all, in: rect)
    }

    private func drawFilterHeader(title: String, active: Bool, in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        let tint = active ? NSColor(BrandTheme.accent(for: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)) : NSColor.labelColor
        // Header cells ignore `alignment` once an attributed string is set, so
        // the centring has to live in the string's paragraph style.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let cell = NSTableHeaderCell(textCell: "")
        cell.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: tint,
                .paragraphStyle: paragraph,
            ]
        )
        cell.draw(withFrame: rect, in: self)
        drawCountryFilterCaret(after: title, font: font, tint: tint, in: rect)
    }

    private func drawCountryFilterCaret(
        after title: String,
        font: NSFont,
        tint: NSColor,
        in rect: NSRect
    ) {
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let halfWidth: CGFloat = 2.5
        let halfHeight: CGFloat = 1.4
        let gap: CGFloat = 2
        let centerX = rect.midX + titleWidth / 2 + gap + halfWidth
        let centerY = rect.midY
        let up: CGFloat = isFlipped ? -1 : 1
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX - halfWidth, y: centerY + up * halfHeight))
        path.line(to: NSPoint(x: centerX, y: centerY - up * halfHeight))
        path.line(to: NSPoint(x: centerX + halfWidth, y: centerY + up * halfHeight))
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        tint.setStroke()
        path.stroke()
    }

    private func drawBoardHeader(
        _ title: String,
        summary: SourceLensDescription,
        tint: NSColor,
        in rect: NSRect
    ) {
        let cell = NSTableHeaderCell(textCell: summary.emphasis)
        cell.alignment = .left
        cell.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        cell.textColor = tint
        cell.lineBreakMode = .byTruncatingTail
        cell.draw(withFrame: rect, in: self)
    }

}

private extension LeaderboardCategory {
    var leftKind: LeaderboardKind { boardKinds[0] }
    var rightKind: LeaderboardKind { boardKinds[1] }

    var leftColumnTitle: String { LeaderboardPresentation.title(leftKind, language: .english) }
    var rightColumnTitle: String { LeaderboardPresentation.title(rightKind, language: .english) }

    func sourceLenses(language: AppLanguage) -> (aa: SourceLensDescription, arena: SourceLensDescription) {
        func lens(_ kind: LeaderboardKind) -> SourceLensDescription {
            SourceLensDescription(
                emphasis: LeaderboardPresentation.explanation(kind, language: language)
            )
        }
        return (lens(leftKind), lens(rightKind))
    }
}

private struct SourceLensDescription {
    let emphasis: String
}

private struct LeaderboardRow: Identifiable {
    let rank: Int
    let left: LeaderboardCellModel?
    let right: LeaderboardCellModel?
    var id: Int { rank }
}

private struct DisplayedLeaderboardEntry {
    let entry: LeaderboardEntry
    let scoreHelp: String?
    let isCompany: Bool
}

private struct LeaderboardCellModel {
    let entry: LeaderboardEntry
    let brandHex: String?
    let logoURL: URL?
    let scoreHelp: String?
    let isCompany: Bool
    var leaderScore: Double? = nil

    func brandColor(isDark: Bool) -> Color? {
        guard let brandHex else { return nil }
        return Color(hex: OrganizationLogoCatalog.displayBrandColorHex(
            brandHex,
            isDark: isDark,
            modelName: isCompany ? nil : entry.name
        ))
    }
}

private extension LeaderboardCellModel {
    static func placeholder(rank: Int) -> LeaderboardCellModel {
        LeaderboardCellModel(
            entry: LeaderboardEntry(rank: rank, name: "Placeholder Model", score: 0),
            brandHex: nil,
            logoURL: nil,
            scoreHelp: nil,
            isCompany: false
        )
    }
}

private struct LeaderboardCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: LeaderboardCellModel?
    let language: AppLanguage
    /// Nil for skeleton placeholders, which must not be copied.
    let onCopyName: ((String) -> Bool)?

    private var entry: LeaderboardEntry? { model?.entry }

    var body: some View {
        HStack(spacing: 10) {
            if let entry {
                ModelLogoView(
                    url: model?.logoURL,
                    pngData: OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: model?.isCompany == true),
                    organization: entry.organization,
                    name: entry.name
                )
                modelName(entry)
                if model?.isCompany == true {
                    InlinePurchaseLinks(organization: entry.organization, modelName: entry.name, language: language)
                }
            } else {
                Text("-")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(cellBackground)
    }

    @ViewBuilder
    private func modelName(_ entry: LeaderboardEntry) -> some View {
        if onCopyName != nil {
            CopyableModelName(
                name: entry.name,
                help: copyHelpText,
                accessibilityLabel: copyAccessibilityLabel(entry),
                onCopy: { onCopyName?(entry.name) ?? false }
            )
        } else if let help = nameHelpText {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(help)
        } else {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Full name stays in the tooltip because the cell truncates the middle.
    private var copyHelpText: String {
        var lines: [String] = []
        if let name = entry?.name, !name.isEmpty {
            lines.append(name)
        }
        lines.append(language.text("Click to copy", "点击复制"))
        if let scoreHelp = model?.scoreHelp {
            lines.append(scoreHelp)
        }
        return lines.joined(separator: "\n")
    }

    private func copyAccessibilityLabel(_ entry: LeaderboardEntry) -> String {
        entry.name + language.text(", click to copy", "，点击复制")
    }

    private var nameHelpText: String? {
        model?.scoreHelp
    }

    private var cellBackground: some View {
        Group {
            if let brandColor = model?.brandColor(isDark: colorScheme == .dark) {
                LeaderboardScoreBackground(color: brandColor.opacity(0.34),
                    score: model?.entry.score ?? 0, leaderScore: model?.leaderScore)
            }
        }
    }
}

private struct OpennessCell: View {
    let model: LeaderboardCellModel?
    let language: AppLanguage

    var body: some View {
        ModelOpennessBadge(model?.entry.resolvedOpenness, language: language, showsTitle: false, iconSize: 11)
            .frame(maxWidth: .infinity, alignment: .center)
            .help(ModelOpenness.help(language: language))
    }
}

private struct CountryCell: View {
    let model: LeaderboardCellModel?
    let language: AppLanguage

    private var country: OrganizationCountry? {
        model.flatMap { OrganizationRegion.country(for: $0.entry) }
    }

    var body: some View {
        Group {
            if let country {
                Text(country.flagEmoji)
                    .font(.system(size: 17))
                    .help(country.localizedName(language: language))
                    .accessibilityLabel(country.localizedName(language: language))
            } else if model != nil {
                UnknownCountryButton(language: language).frame(height: 20)
            } else {
                Text("-")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }
}

private struct ScoreCell: View {
    let model: LeaderboardCellModel?
    let scoreDigits: Int
    let shareColor: Color

    var body: some View {
        Group {
            if let entry = model?.entry {
                Text(entry.score.formatted(.number.precision(.fractionLength(scoreDigits))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .bottom) {
                        let share = LeaderboardPresentation.scoreShareText(entry.score, leaderScore: model?.leaderScore)
                        if !share.isEmpty {
                            Text(share).font(.system(size: 8)).monospacedDigit()
                                .foregroundStyle(shareColor).offset(y: 9)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                Text("-")
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(OptionalHelp(text: model?.scoreHelp))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

private struct InlinePurchaseLinks: View {
    let organization: String?
    let modelName: String
    let language: AppLanguage

    private var links: PurchaseLinks {
        PurchaseLinkCatalog.links(forOrganization: organization, modelName: modelName)
    }

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: 10) {
                PurchaseLinkControl(title: language.text("Plan", "套餐"), links: links.codingPlan, language: language)
                PurchaseLinkControl(title: language.text("Pay as you go", "按量"), links: links.payAsYouGo, language: language)
            }
            .font(.caption)
        }
    }
}

private struct PurchaseLinkControl: View {
    let title: String
    let links: [PurchaseLink]
    let language: AppLanguage

    var body: some View {
        if let link = PurchaseLinkCatalog.preferredLink(from: links, language: language) {
            // SwiftUI Link shows the pointing-hand cursor and opens the URL
            // itself; an onHover-based cursor here would swallow clicks in
            // NSTableView-backed cells.
            Link(title, destination: link.url)
                .font(.caption)
                .help(link.url.absoluteString)
        }
    }
}

private struct CategorySegmentedControl: NSViewRepresentable {
    static let width: CGFloat = 360
    static let height: CGFloat = 24

    let language: AppLanguage
    @Binding var selection: LeaderboardCategory

    private func label(_ category: LeaderboardCategory) -> String {
        switch category {
        case .general: language.text("General", "综合")
        case .coding: language.text("Coding", "编程")
        case .image: language.text("Image", "图片")
        case .video: language.text("Video", "视频")
        }
    }

    private func configureLabels(_ control: NSSegmentedControl) {
        for (index, category) in LeaderboardCategory.allCases.enumerated() {
            control.setLabel(label(category), forSegment: index)
        }
        control.toolTip = language.text("Switch leaderboard category", "切换榜单类别")
        control.setAccessibilityLabel(language.text("Leaderboard category", "榜单类别"))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> CategorySegmentedControlView {
        let control = CategorySegmentedControlView()
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        // Selected labels are heavier. Content-sized segments then change width
        // and the whole control jitters. Equal widths stay put.
        control.segmentDistribution = .fillEqually
        control.segmentCount = LeaderboardCategory.allCases.count
        let segmentWidth = Self.width / CGFloat(LeaderboardCategory.allCases.count)
        for (index, _) in LeaderboardCategory.allCases.enumerated() {
            control.setWidth(segmentWidth, forSegment: index)
        }
        configureLabels(control)
        control.selectedSegment = selectedIndex
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: CategorySegmentedControlView, context: Context) {
        context.coordinator.selection = $selection
        configureLabels(control)
        let index = selectedIndex
        guard control.selectedSegment != index else { return }
        // A SwiftUI refresh must not replay the click animation.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        control.selectedSegment = index
        NSAnimationContext.endGrouping()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: CategorySegmentedControlView,
        context: Context
    ) -> CGSize? {
        CGSize(width: Self.width, height: Self.height)
    }

    private var selectedIndex: Int {
        LeaderboardCategory.allCases.firstIndex(of: selection) ?? 0
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<LeaderboardCategory>

        init(selection: Binding<LeaderboardCategory>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard LeaderboardCategory.allCases.indices.contains(index) else { return }
            let category = LeaderboardCategory.allCases[index]
            guard selection.wrappedValue != category else { return }
            selection.wrappedValue = category
        }
    }
}

private struct GroupingSegmentedControl: NSViewRepresentable {
    static let width: CGFloat = 180
    static let height: CGFloat = 24

    let language: AppLanguage
    @Binding var selection: LeaderboardGrouping

    private func label(_ grouping: LeaderboardGrouping) -> String {
        switch grouping {
        case .model: language.text("Models", "模型")
        case .company: language.text("Companies", "公司")
        }
    }

    private func configureLabels(_ control: NSSegmentedControl) {
        for (index, grouping) in LeaderboardGrouping.allCases.enumerated() {
            control.setLabel(label(grouping), forSegment: index)
        }
        control.toolTip = language.text("Company scores use each company's strongest model.", "按公司查看时，以最强模型分数为准，弱型号不拉低")
        control.setAccessibilityLabel(language.text("Leaderboard grouping", "榜单分组"))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> CategorySegmentedControlView {
        let control = CategorySegmentedControlView()
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        // Selected labels are heavier. Content-sized segments then change width
        // and the whole control jitters. Equal widths stay put.
        control.segmentDistribution = .fillEqually
        control.segmentCount = LeaderboardGrouping.allCases.count
        let segmentWidth = Self.width / CGFloat(LeaderboardGrouping.allCases.count)
        for (index, _) in LeaderboardGrouping.allCases.enumerated() {
            control.setWidth(segmentWidth, forSegment: index)
        }
        configureLabels(control)
        control.selectedSegment = selectedIndex
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: CategorySegmentedControlView, context: Context) {
        context.coordinator.selection = $selection
        configureLabels(control)
        let index = selectedIndex
        guard control.selectedSegment != index else { return }
        // A SwiftUI refresh must not replay the click animation.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        control.selectedSegment = index
        NSAnimationContext.endGrouping()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: CategorySegmentedControlView,
        context: Context
    ) -> CGSize? {
        CGSize(width: Self.width, height: Self.height)
    }

    private var selectedIndex: Int {
        LeaderboardGrouping.allCases.firstIndex(of: selection) ?? 0
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<LeaderboardGrouping>

        init(selection: Binding<LeaderboardGrouping>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard LeaderboardGrouping.allCases.indices.contains(index) else { return }
            let grouping = LeaderboardGrouping.allCases[index]
            guard selection.wrappedValue != grouping else { return }
            selection.wrappedValue = grouping
        }
    }
}

/// The menu-bar popover is not key until the click, so the control has to
/// accept that first mouse or the tab will not switch.
private final class CategorySegmentedControlView: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Command Line Tools do not ship the SwiftUI `@State` macro, so the brief
/// copied flash cannot live in view state.
@MainActor
private final class NameCopyFlash: ObservableObject {
    @Published var copied = false
    private var token = 0

    func note() {
        token += 1
        let token = token
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard self.token == token else { return }
            copied = false
        }
    }
}

/// Visible name, with a first-mouse button behind it. A SwiftUI tap is swallowed
/// by the NSTableView cell, and this popover is not key until the click.
private struct CopyableModelName: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var flash = NameCopyFlash()

    let name: String
    let help: String
    let accessibilityLabel: String
    let onCopy: () -> Bool

    var body: some View {
        nameLabel
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                CopyNameButton(
                    help: help,
                    accessibilityLabel: accessibilityLabel,
                    onClick: copy
                )
            }
            .animation(.easeOut(duration: 0.15), value: flash.copied)
    }

    @ViewBuilder
    private var nameLabel: some View {
        let label = Text(name)
            .lineLimit(1)
            .truncationMode(.middle)
        if flash.copied {
            label.foregroundStyle(copiedInk)
        } else {
            label
        }
    }

    private var copiedInk: Color {
        colorScheme == .dark
            ? Color(red: 0.49, green: 0.84, blue: 0.55)
            : Color(red: 0.10, green: 0.52, blue: 0.26)
    }

    private func copy() {
        guard onCopy() else { return }
        flash.note()
    }
}

private struct CopyNameButton: NSViewRepresentable {
    let help: String
    let accessibilityLabel: String
    let onClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick)
    }

    func makeNSView(context: Context) -> CopyNameButtonView {
        let button = CopyNameButtonView()
        button.isTransparent = true
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: CopyNameButtonView, context: Context) {
        configure(button, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CopyNameButtonView, context: Context) -> CGSize? {
        // An empty proposal must not collapse the hit target to 0×0. Nil lets
        // SwiftUI use the label size; a real proposal fills that label.
        guard let width = proposal.width, let height = proposal.height, width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func configure(_ button: CopyNameButtonView, context: Context) {
        context.coordinator.onClick = onClick
        button.coordinator = context.coordinator
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(help)
    }

    final class Coordinator: NSObject {
        var onClick: () -> Void

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
        }

        func click() {
            onClick()
        }
    }
}

private final class CopyNameButtonView: NSButton {
    weak var coordinator: CopyNameButton.Coordinator?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        coordinator?.click()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        coordinator?.click()
        return true
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        PointingHandCursorRegistry.shared.enter(self)
    }

    override func mouseEntered(with event: NSEvent) {
        PointingHandCursorRegistry.shared.enter(self)
    }

    override func mouseExited(with event: NSEvent) {
        PointingHandCursorRegistry.shared.exit(self)
    }
}


private struct ModelLogoView: View {
    let url: URL?
    let pngData: Data?
    let organization: String?
    let name: String

    var body: some View {
        logoContent
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var logoContent: some View {
        if let pngData, let image = NSImage(data: pngData) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let bundled = bundledLogoURL, let image = NSImage(contentsOf: bundled) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                placeholder
            }
        }
    }

    private var bundledLogoURL: URL? {
        guard let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organization, modelName: name),
              let resourceURL = Bundle.main.resourceURL else { return nil }
        for ext in ["png", "ico", "jpg"] {
            let candidate = resourceURL.appending(path: "logos/" + key + "." + ext)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
    }

    private var placeholder: some View {
        Text(OrganizationLogoCatalog.initial(organization: organization, modelName: name))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.black.opacity(0.65))
            .frame(width: 20, height: 20)
            .background(.white)
    }
}

/// Pointing hand from an AppKit tracking area, never from `NSCursor` push/pop.
///
/// Hover cannot keep that stack balanced: SwiftUI can deliver the next
/// control's enter before this control's exit, rebuilding the footer on a
/// language switch drops a hovered view without an exit, and closing the
/// popover swallows it. Every miss left a stray hand on the stack, so the next
/// AppKit pop landed on that hand instead of the arrow and the whole footer
/// wore the pointer.
private struct PointingHandCursor: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.background(
            PointingHandCursorTracker(isEnabled: isEnabled)
                .allowsHitTesting(false)
        )
    }
}

private struct PointingHandCursorTracker: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> PointingHandCursorTrackerView {
        let view = PointingHandCursorTrackerView()
        view.isCursorHintEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: PointingHandCursorTrackerView, context: Context) {
        nsView.isCursorHintEnabled = isEnabled
    }
}

private final class PointingHandCursorTrackerView: NSView {
    var isCursorHintEnabled = true {
        didSet {
            guard isCursorHintEnabled != oldValue else { return }
            if !isCursorHintEnabled {
                PointingHandCursorRegistry.shared.exit(self)
            }
            updateTrackingAreas()
        }
    }

    /// A cursor hint must not take the click from the control it decorates.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard isCursorHintEnabled else { return }
        // The popover is not key until the first click, so the hint has to stay
        // live in an inactive window.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        PointingHandCursorRegistry.shared.enter(self)
    }

    override func cursorUpdate(with event: NSEvent) {
        PointingHandCursorRegistry.shared.enter(self)
    }

    override func mouseExited(with event: NSEvent) {
        PointingHandCursorRegistry.shared.exit(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            PointingHandCursorRegistry.shared.exit(self)
        }
    }
}

/// Single owner of the panel's pointing hand.
///
/// `set()` leaves AppKit's cursor stack alone, and the arrow returns only once
/// no hint still holds the mouse, so overlapping enter/exit deliveries cannot
/// pin the pointer over inert controls.
@MainActor
final class PointingHandCursorRegistry {
    static let shared = PointingHandCursorRegistry()

    private let hovered = NSHashTable<NSView>.weakObjects()

    func enter(_ view: NSView) {
        hovered.add(view)
        NSCursor.pointingHand.set()
    }

    func exit(_ view: NSView) {
        hovered.remove(view)
        dropViewsThatLostTheMouse()
        if hovered.allObjects.isEmpty {
            NSCursor.arrow.set()
        }
    }

    /// Closing the popover can swallow the exit of a hovered control. Give the
    /// hand back with the window instead of carrying it into the next open.
    func reset() {
        hovered.removeAllObjects()
        NSCursor.arrow.set()
    }

    /// A view torn down while hovered never reports its exit, and a stale entry
    /// would hold the hand over the whole panel. Trust geometry, not delivery.
    private func dropViewsThatLostTheMouse() {
        for view in hovered.allObjects where !containsMouse(view) {
            hovered.remove(view)
        }
    }

    private func containsMouse(_ view: NSView) -> Bool {
        guard let window = view.window, window.isVisible,
              !view.isHiddenOrHasHiddenAncestor else { return false }
        return view.bounds.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursor(isEnabled: isEnabled))
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

extension Color {
    init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
