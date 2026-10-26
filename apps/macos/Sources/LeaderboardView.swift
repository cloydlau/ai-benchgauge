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
    @Published var modelDetails: LeaderboardEntry?
}

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    @StateObject private var screenshot = ScreenshotUIState()
    @StateObject private var search = DesktopLeaderboardSearchState()

    private var language: AppLanguage { state.selectedLanguage }
    private func tr(_ english: String, _ chinese: String) -> String {
        language.text(english, chinese)
    }

    private static let minimumWidth: CGFloat = 850
    // macOS Table adds its own padding around fixed-width columns.
    private static let rankColumnWidth: CGFloat = 36
    private static let countryColumnWidth: CGFloat = 32
    private static let opennessColumnWidth: CGFloat = 32
    /// Row height SwiftUI settles on for these cells. The panel height has to
    /// preserve the existing viewport; additional rows scroll inside it.
    private static let tableRowHeight: CGFloat = 32
    /// `.tableStyle(.bordered)` insets the clip view by 1pt top and bottom, so
    /// the rows need 2pt more than the table frame hands them.
    private static let tableBorderHeight: CGFloat = 2
    static let distributionRowCount = 13

    let maximumWidth: CGFloat
    var viewportSize: CGSize? = nil

    private var contentWidth: CGFloat {
        viewportSize?.width ?? Self.preferredWidth(for: state, maximumWidth: maximumWidth)
    }

    private var contentHeight: CGFloat {
        viewportSize?.height ?? Self.preferredHeight(for: state, width: contentWidth, maximumWidth: maximumWidth)
    }

    private var nameColumnWidth: CGFloat {
        max(40, (contentWidth - Self.tableChromeWidth(boardCount: visibleKinds.count, includesUsage: visibleKinds.contains(.openRouterUsage))) / CGFloat(visibleKinds.count))
    }

    private static func tableChromeWidth(boardCount: Int, includesUsage: Bool = false) -> CGFloat {
        // Rank, four native cell insets per source, country/source icons, score.
        52 + CGFloat(boardCount) * 192 + (includesUsage ? 30 : 0)
    }

    static func preferredWidth(for state: AppState, maximumWidth: CGFloat) -> CGFloat {
        let measured = state.panelLayoutCache.columnWidth(revision: state.snapshotRevision, language: state.selectedLanguage) {
            measuredNameColumnWidth(for: state)
        }
        let kinds = state.visibleBoardKinds
        let desired = max(minimumWidth, ceil(measured * CGFloat(kinds.count)
            + tableChromeWidth(boardCount: kinds.count, includesUsage: kinds.contains(.openRouterUsage)) + 88))
        return min(desired, maximumWidth)
    }

    private static func measuredNameColumnWidth(for state: AppState) -> CGFloat {
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
        let headerWidth = LeaderboardCategory.allCases.flatMap(\.boardKinds).map { kind in
            let time = LeaderboardPresentation.sourceTime(state.snapshot.boards[kind], language: state.selectedLanguage)
            return SourceTableHeaderView.requiredNameColumnWidth(
                title: LeaderboardPresentation.columnTitle(kind, language: state.selectedLanguage),
                licenseName: headerLicenseName(kind: kind, board: state.snapshot.boards[kind]),
                summary: SourceLensDescription(emphasis: LeaderboardPresentation.explanation(kind, language: state.selectedLanguage)),
                time: time)
        }.max() ?? 0
        return max(columnWidth, headerWidth)
    }

    static func preferredSize(for state: AppState, maximumWidth: CGFloat) -> NSSize {
        let width = preferredWidth(for: state, maximumWidth: maximumWidth)
        return NSSize(width: width, height: preferredHeight(for: state, width: width, maximumWidth: maximumWidth))
    }

    static func preferredHeight(for state: AppState, width: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        state.panelLayoutCache.height(for: state, width: width, maximumWidth: maximumWidth) {
            measuredHeight(for: state, width: width, maximumWidth: maximumWidth)
        }
    }

    private static func measuredHeight(for state: AppState, width: CGFloat, maximumWidth: CGFloat) -> CGFloat {
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
        let kinds = state.visibleBoardKinds
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
            table.overlay {
                if state.selectedCategory == .usage, visibleKinds.allSatisfy({ state.snapshot.boards[$0]?.entries.isEmpty ?? true }) {
                    VStack(spacing: 10) {
                        if state.isRefreshing {
                            ProgressView()
                            Text(tr("Loading usage data…", "正在加载用量数据…"))
                                .accessibilityIdentifier("usage-loading")
                        } else if visibleKinds.contains(where: { state.lastErrors[$0] != nil }) {
                            Text(tr("Could not load usage data", "用量数据加载失败"))
                                .accessibilityIdentifier("usage-error")
                            ForEach(visibleKinds, id: \.self) { kind in
                                if let error = state.lastErrors[kind] {
                                    Text(kind.sourcePrefix + " · " + error).font(.caption)
                                }
                            }
                        } else {
                            Text(tr("No usage data yet", "暂无用量数据"))
                                .accessibilityIdentifier("usage-empty")
                        }
                    }.multilineTextAlignment(.center).padding(24).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BrandTheme.background(for: colorScheme))
                }
            }
            if screenshot.isCapturing, state.selectedCategory == .usage {
                Text(visibleKinds.compactMap { state.snapshot.boards[$0]?.sourceNote }.joined(separator: "\n\n"))
                    .font(.system(size: 9)).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: contentWidth, height: contentHeight)
        .background(BrandTheme.background(for: colorScheme))
        .tint(BrandTheme.accent(for: colorScheme))
        .accentColor(BrandTheme.accent(for: colorScheme))
        .sheet(item: $screenshot.licenseSection) { section in
            LicenseNoticesView(section: section, language: language,
                               cloudbaseSourceNote: state.snapshot.boards[.cloudbaseUsage]?.sourceNote,
                               vercelSourceNote: state.snapshot.boards[.vercelUsage]?.sourceNote,
                               openRouterSourceNote: state.snapshot.boards[.openRouterUsage]?.sourceNote)
        }
        .sheet(isPresented: $screenshot.showOfficialAccounts) {
            OfficialQuotaAccountsView(state: state, onClose: { screenshot.showOfficialAccounts = false })
        }
        .sheet(item: $screenshot.modelDetails) { entry in
            ModelDetailsView(entry: entry, language: language, copyName: copyDisplayedName,
                close: { screenshot.modelDetails = nil }).frame(width: 560, height: 620)
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
                .frame(maxWidth: .infinity, alignment: .center)
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

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleKinds.count == 1 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        brandHeading.fixedSize()
                        Spacer(minLength: 0)
                        navigationPickers
                        Spacer(minLength: 0)
                        freshness.fixedSize()
                    }
                    stackedTitleRow
                }
            } else if contentWidth >= (language == .english ? 1300 : 1100) {
                HStack(spacing: 12) {
                    brandHeading.frame(maxWidth: .infinity, alignment: .leading)
                    navigationPickers
                    freshness.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                stackedTitleRow
            }
        }
    }

    private var navigationPickers: some View {
        DesktopLeaderboardSearchNavigation(state: search, language: language) {
            HStack(spacing: 8) { groupingPicker; categoryPicker }
        }
    }

    private var stackedTitleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                brandHeading
                Spacer(minLength: 12)
                freshness
            }
            navigationPickers.frame(maxWidth: .infinity)
        }
    }

    private var brandHeading: some View {
        HStack(alignment: .center, spacing: 8) {
            appTitle.fixedSize()
            FeatureSubtitle(language: language,
                height: max(12, BrandTitleMetrics.inkHeight(language: language) - 3),
                multiline: true, showsHelpSymbol: false)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("brand-subtitle")
        }
    }

    @ViewBuilder private var appTitle: some View {
        Group {
            if language == .english { EnglishBrandTitle(fontSize: 21) }
            else { ChineseBrandTitle() }
        }.accessibilityIdentifier("brand-title")
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            freshnessLine(now: context.date)
        }
    }

    private var groupingPicker: some View {
        GroupingSegmentedControl(
            language: language,
            compact: visibleKinds.count == 1,
            selection: Binding(
                get: { state.selectedGrouping },
                set: { state.selectGrouping($0) }
            )
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: GroupingSegmentedControl.height)
        .help(tr("Benchmark company scores use the strongest model; usage sums listed models.", "公司测评取最强模型分数；用量汇总榜内模型"))
    }

    private var categoryPicker: some View {
        CategorySegmentedControl(
            language: language,
            compact: visibleKinds.count == 1,
            selection: Binding(
                get: { state.selectedCategory },
                set: { state.selectCategory($0) }
            )
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: CategorySegmentedControl.height)
        .help(tr("Switch leaderboard category", "切换榜单类别"))
    }

    private var visibleKinds: [LeaderboardKind] { state.visibleBoardKinds }
    private func kind(at slot: Int) -> LeaderboardKind { visibleKinds.indices.contains(slot) ? visibleKinds[slot] : visibleKinds[0] }
    private func shareColor(for kind: LeaderboardKind) -> Color {
        Color(hex: SourceTabTheme.palette(for: kind, dark: colorScheme == .dark).accent)!
    }


    private var selectedCategory: LeaderboardCategory {
        state.selectedCategory
    }

    /// Leaderboard times belong to their source columns; this row tracks only
    /// the local quota snapshot.
    private func freshnessLine(now: Date) -> some View {
        Group {
            if let quota = quotaClause(now: now, format: .relative) {
                Text(quota)
                    .foregroundStyle(state.quotaUnavailable ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(freshnessAccessibilityLabel(now: now))
        .help(freshnessHelp(now: now))
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

    private func freshnessSummary(now: Date) -> String {
        quotaClause(now: now, format: .both) ?? ""
    }

    private func freshnessAccessibilityLabel(now: Date) -> String {
        freshnessSummary(now: now)
    }

    private func freshnessHelp(now: Date) -> String {
        var parts = [freshnessSummary(now: now)]
        if state.quotaUnavailable {
            parts.append(tr("Quota refresh failed; showing previous values", "余量数据库这次没有读成，显示的是上次余量"))
        } else if !state.quotaChips.isEmpty {
            parts.append(tr("Quota comes from this Mac's CC Switch data", "余量来自本机 CC Switch"))
        }
        return parts.joined(separator: tr(". ", "。"))
    }

    private func quotaClause(now: Date, format: FreshnessFormat) -> String? {
        if state.quotaChips.isEmpty {
            return state.quotaUnavailable ? tr("Quota unavailable", "余量 暂不可读") : nil
        }
        guard let updatedAt = state.quotaUpdatedAt else { return tr("Quota pending", "余量 待更新") }
        let value = freshnessValue(updatedAt, now: now, format: format)
        switch format {
        case .relative: return tr("Quotas updated \(value)", "余量\(value)更新")
        case .stamp, .both: return tr("Quotas updated \(value)", "余量更新于\(value)")
        }
    }

    // Three native source slots preserve macOS 14.0 support. AppKit hides
    // unused columns completely, rather than leaving empty source placeholders.
    @TableColumnBuilder<LeaderboardRow, Never>
    private func boardColumns(_ slot: Int) -> some TableColumnContent<LeaderboardRow, Never> {
        TableColumn(LeaderboardPresentation.columnTitle(kind(at: slot), language: language)) { row in
            LeaderboardCell(model: row.cells[slot], language: language, shareColor: shareColor(for: kind(at: slot)),
                columnWidth: nameColumnWidth, onSelectName: nameAction)
        }.width(nameColumnWidth)
        TableColumn(tr("Country", "国家")) { row in
            CountryCell(model: row.cells[slot], language: language)
        }.width(Self.countryColumnWidth).alignment(.center)
        TableColumn(ModelOpenness.columnTitle(language: language)) { row in
            OpennessCell(model: row.cells[slot], language: language)
        }.width(Self.opennessColumnWidth).alignment(.center)
        TableColumn(LeaderboardPresentation.scoreTitle(kind(at: slot), language: language)) { row in
            ScoreCell(model: row.cells[slot], kind: kind(at: slot))
        }.width(kind(at: slot) == .openRouterUsage ? 90 : 60).alignment(.center)
    }

    private var table: some View {
        let renderedRows = rows
        return Table(renderedRows) {
            TableColumn(tr("Rank", "排名")) { row in
                Text(row.isDistribution ? "" : LeaderboardPresentation.rankLabel(row.rank)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }.width(Self.rankColumnWidth).alignment(.center)
            boardColumns(0)
            boardColumns(1)
            boardColumns(2)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .scrollIndicators(.automatic)
        .overlay(TableChrome(
            boards: visibleKinds.map { kind in
                let time = LeaderboardPresentation.sourceTime(state.snapshot.boards[kind], language: language)
                return BoardHeaderConfiguration(kind: kind,
                    licenseName: headerLicenseName(kind: kind, board: state.snapshot.boards[kind]),
                    summary: SourceLensDescription(emphasis: LeaderboardPresentation.explanation(kind, language: language)),
                    time: time,
                    polishReady: !state.isRefreshing && !screenshot.isCapturing && state.snapshot.boards[kind] != nil && kind != .cloudbaseUsage,
                    polishRevision: state.timestampPolishRevision,
                    help: LeaderboardPresentation.columnTitle(kind, language: language) + "\n" + LeaderboardPresentation.sourceHelp(kind, language: language, board: state.snapshot.boards[kind]),
                    country: state.countryFilters[kind] ?? .all,
                    countryOptions: countryOptions(for: kind), openness: state.opennessFilters[kind] ?? .all)
            }, language: language,
            onOpennessFilter: { state.selectOpennessFilter($1, for: $0) },
            onCountryFilter: { state.selectCountryFilter($1, for: $0) },
            showsSkeleton: needsSkeleton, distributionStartRow: renderedRows.count - Self.distributionRowCount, distributionView: AnyView(distributionPanels)))
        .overlay {
            if !needsSkeleton, !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !renderedRows.contains(where: { !$0.isDistribution && $0.cells.contains(where: { $0 != nil }) }) {
                Text(tr("No matching results", "没有匹配结果"))
                    .foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .top).padding(.top, 52).allowsHitTesting(false)
            }
        }
        .id("\(contentWidth)-\(visibleKinds.map(\.rawValue).joined(separator: ","))")
        .redacted(reason: needsSkeleton ? .placeholder : [])
        .disabled(needsSkeleton)
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
    private var nameAction: ((LeaderboardEntry) -> Bool)? {
        guard !needsSkeleton else { return nil }
        return { entry in
            guard !screenshot.isCapturing, !state.isQuitting else { return false }
            if state.selectedGrouping == .company { return copyDisplayedName(entry.name) }
            screenshot.modelDetails = entry
            return false
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
            footerRow(compact: false)
            footerRow(compact: true)
            footerRow(compact: true, stacked: true)
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
                    Text(visibleKinds.map(\.sourceLinkTitle).joined(separator: " · "))
                    Text("·")
                }
                Text("Cloyd Lau · MIT License")
            }
            .fixedSize()
        }
    }

    private func footerRow(compact: Bool, stacked: Bool = false) -> some View {
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
                DataSourcesPicker(language: language)
                    .fixedSize()
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

    private var boardVisibilityMenu: some View {
        BoardVisibilityPicker(language: language, category: selectedCategory,
            selected: visibleKinds, onConfirm: { state.setVisibleBoards($0) })
            .fixedSize()
    }

    private func footerControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 7) {
            boardVisibilityMenu
            Text("·")
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
        state.selectedCategory != .usage && visibleKinds.allSatisfy { state.snapshot.boards[$0]?.entries.isEmpty ?? true }
    }

    private var distributionPanels: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(visibleKinds, id: \.self) { kind in
                LeaderboardDistributionCharts(entries: state.snapshot.boards[kind]?.entries ?? [], language: language,
                    boardTitle: LeaderboardPresentation.columnTitle(kind, language: language))
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(BrandTheme.background(for: colorScheme)).environment(\.colorScheme, colorScheme).unredacted()
    }

    private var rows: [LeaderboardRow] {
        let data = rankingRows
        return data + (0..<Self.distributionRowCount).map { offset in
            LeaderboardRow(rank: data.count + offset + 1, cells: Array(repeating: nil, count: 3), isDistribution: true)
        }
    }

    private var rankingRows: [LeaderboardRow] {
        if needsSkeleton {
            return (0..<Self.visibleRowCount(for: state)).map { index in
                LeaderboardRow(rank: index + 1, cells: Array(repeating: .placeholder(rank: index + 1), count: 3))
            }
        }
        let unsearched = visibleKinds.map { displayedEntries(kind: $0) }
        let matches = LeaderboardPresentation.modelNameMatcher(search.query)
        let entries = unsearched.map { $0.filter { matches($0.entry.name) } }
        let logos = organizationLogos
        let resultCount = entries.map(\.count).max() ?? 0
        let count = search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? max(Self.visibleRowCount(for: state), resultCount) : max(4, resultCount)
        return (0..<count).map { index in
            let cells = (0..<3).map { slot -> LeaderboardCellModel? in
                guard entries.indices.contains(slot) else { return nil }
                let list = entries[slot]
                return cellModel(for: index < list.count ? list[index] : nil, organizationLogos: logos,
                    leaderScore: unsearched[slot].first?.entry.score, showRelativeShare: !visibleKinds[slot].isShareUsage)
            }
            return LeaderboardRow(rank: index + 1, cells: cells)
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
                scoreHelp: CompanyLeaderboard.scoreHelp(for: standing, language: language, kind: board?.kind),
                isCompany: true
            )
        }
    }

    private func countryOptions(for kind: LeaderboardKind) -> [LeaderboardCountryFilter] {
        LeaderboardPresentation.countryFilters(state.snapshot.boards[kind])
    }

    private func cellModel(
        for displayed: DisplayedLeaderboardEntry?,
        organizationLogos: [String: URL], leaderScore: Double?, showRelativeShare: Bool
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
            showRelativeShare: showRelativeShare, leaderScore: leaderScore
        )
    }

    private var organizationLogos: [String: URL] {
        var logos: [String: URL] = [:]
        for kind in visibleKinds {
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
/// one-line header with the source name leading and its own data time trailing.
private func headerLicenseName(kind: LeaderboardKind, board: Leaderboard?) -> String? {
    kind == .epochECI || (kind.isUsage && kind != .cloudbaseUsage) || ArenaAttribution.applies(board) ? "CC BY 4.0" : nil
}

private struct BoardHeaderConfiguration {
    let kind: LeaderboardKind
    let licenseName: String?
    let summary: SourceLensDescription
    let time: (text: String, isSourceTime: Bool)
    let polishReady: Bool
    let polishRevision: Int
    let help: String
    let country: LeaderboardCountryFilter
    let countryOptions: [LeaderboardCountryFilter]
    let openness: LeaderboardOpennessFilter
}

private struct TableChrome: NSViewRepresentable {
    let boards: [BoardHeaderConfiguration]
    let language: AppLanguage
    let onOpennessFilter: (LeaderboardKind, LeaderboardOpennessFilter) -> Void
    let onCountryFilter: (LeaderboardKind, LeaderboardCountryFilter) -> Void
    let showsSkeleton: Bool
    let distributionStartRow: Int
    let distributionView: AnyView

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: ProbeView, context: Context) {
        view.configure(boards: boards, language: language, onOpennessFilter: onOpennessFilter,
            onCountryFilter: onCountryFilter, showsSkeleton: showsSkeleton, distributionStartRow: distributionStartRow, distributionView: distributionView)
    }

    final class ProbeView: NSView {
        private var boards: [BoardHeaderConfiguration] = []
        private var language = AppLanguage.english
        private var onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?
        private var onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?
        private var showsSkeleton = false
        private weak var rankingScrollView: NSScrollView?
        private weak var rankingTableView: NSTableView?
        private var backToTopButton: NSButton?
        private var updateScheduled = false
        private var needsConfiguration = true
        private var distributionStartRow = 0
        private var distributionView = AnyView(EmptyView())
        private var distributionHost: NSHostingView<AnyView>?
        private weak var distributionTable: NSTableView?

        private func configureDistributions(in table: NSTableView) {
            guard distributionStartRow >= 0, distributionStartRow < table.numberOfRows else { return }
            if distributionTable !== table {
                if let previous = distributionTable {
                    NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: previous)
                }
                distributionTable = table
                table.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(distributionGeometryChanged),
                    name: NSView.frameDidChangeNotification, object: table)
            }
            let host = distributionHost ?? NSHostingView(rootView: distributionView)
            distributionHost = host
            host.rootView = distributionView
            host.identifier = NSUserInterfaceItemIdentifier("desktop-distributions")
            host.sizingOptions = []
            host.wantsLayer = true; host.layer?.zPosition = 10
            guard let clip = table.enclosingScrollView?.contentView else { return }
            // NSTableView recycles row subviews above its own children while scrolling.
            // Keep the footer beside its document view so recycled cells cannot cover it.
            if host.superview !== clip { clip.addSubview(host, positioned: .above, relativeTo: table) }
            positionDistributions(in: table)
        }

        private func positionDistributions(in table: NSTableView) {
            guard let host = distributionHost, let clip = host.superview,
                  distributionStartRow < table.numberOfRows else { return }
            let first = table.rect(ofRow: distributionStartRow), last = table.rect(ofRow: table.numberOfRows - 1)
            let frame = table.convert(NSRect(x: 0, y: first.minY, width: table.bounds.width, height: last.maxY - first.minY), to: clip)
            if host.frame != frame { host.frame = frame }
        }

        @objc private func distributionGeometryChanged() {
            guard let table = distributionTable else { return }
            positionDistributions(in: table)
            // Variable-height rows can finalize their metrics after the document frame changes.
            DispatchQueue.main.async { [weak self, weak table] in
                guard let self, let table, self.distributionTable === table else { return }
                self.positionDistributions(in: table)
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func scrollPositionChanged() {
            guard let scroll = rankingScrollView else { return }
            if let table = rankingTableView { positionDistributions(in: table) }
            let hidden = scroll.contentView.bounds.minY < 32
            if backToTopButton?.isHidden != hidden { backToTopButton?.isHidden = hidden }
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

        func configure(boards: [BoardHeaderConfiguration], language: AppLanguage,
            onOpennessFilter: @escaping (LeaderboardKind, LeaderboardOpennessFilter) -> Void,
            onCountryFilter: @escaping (LeaderboardKind, LeaderboardCountryFilter) -> Void, showsSkeleton: Bool, distributionStartRow: Int, distributionView: AnyView) {
            self.boards = boards
            self.language = language
            self.onOpennessFilter = onOpennessFilter
            self.onCountryFilter = onCountryFilter
            self.showsSkeleton = showsSkeleton
            self.distributionStartRow = distributionStartRow
            self.distributionView = distributionView
            needsConfiguration = true
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
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard let window = self.window, let root = window.contentView else { return }
                // A scroll relayout must not walk every realized SwiftUI cell.
                // Re-discover only when SwiftUI replaces or detaches the table.
                if let table = self.rankingTableView, table.window === window,
                   let scroll = table.enclosingScrollView, scroll === self.rankingScrollView {
                    self.positionDistributions(in: table)
                    if self.needsConfiguration || !(table.headerView is SourceTableHeaderView) {
                        self.configureRankingScroll(scroll)
                        self.configureHeader(in: table, scrollView: scroll)
                        self.configureDistributions(in: table)
                        self.needsConfiguration = false
                    }
                    return
                }
                guard let table = Self.findRankingTable(in: root),
                      let scroll = table.enclosingScrollView else { return }
                self.rankingTableView = table
                scroll.hasHorizontalScroller = true
                scroll.horizontalScrollElasticity = .none
                self.configureRankingScroll(scroll)
                self.configureHeader(in: table, scrollView: scroll)
                self.configureDistributions(in: table)
                self.needsConfiguration = false
            }
        }

        private static func findRankingTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.tableColumns.count >= 9 { return table }
            for child in view.subviews {
                if let table = findRankingTable(in: child) { return table }
            }
            return nil
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
            for (index, column) in tableView.tableColumns.enumerated() {
                column.isHidden = index > 0 && (index - 1) / 4 >= boards.count
                guard index > 0, !column.isHidden else { continue }
                let board = boards[(index - 1) / 4]
                switch (index - 1) % 4 {
                case 0: column.headerToolTip = board.help
                case 1: column.headerToolTip = language.text("Filter by country", "按国家筛选")
                case 2: column.headerToolTip = language.text("Filter by source. ", "按源码筛选。") + ModelOpenness.help(language: language)
                default: break
                }
            }
            header.configure(boards: boards, language: language, onOpennessFilter: onOpennessFilter,
                onCountryFilter: onCountryFilter, showsSkeleton: showsSkeleton)
        }
    }
}

private final class SourceTableHeaderView: NSTableHeaderView {
    static let height: CGFloat = 34
    // Keep the pinned labels readable even when the system makes table chrome vibrant.
    override var allowsVibrancy: Bool { false }
    override var isOpaque: Bool { false }
    private var boards: [BoardHeaderConfiguration] = []
    private var language = AppLanguage.english
    private var onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?
    private var onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?
    private var showsSkeleton = false
    private var menuChoices: [LeaderboardCountryFilter] = []
    private var menuKind: LeaderboardKind?
    private var polishSchedules: [LeaderboardKind: TimestampPolishSchedule] = [:]
    private var polishRevisions: [LeaderboardKind: Int] = [:]
    private var timeRects: [LeaderboardKind: NSRect] = [:]
    private var polishTimer: Timer?
    private var fixedPolishPhase: Double? {
        ProcessInfo.processInfo.environment["BENCHGAUGE_TIMESTAMP_POLISH_PHASE"].flatMap(Double.init)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updatePolish), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updatePolish),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    isolated deinit {
        polishTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePolish() }

    @objc private func updatePolish() {
        polishTimer?.invalidate(); polishTimer = nil
        let now = ProcessInfo.processInfo.systemUptime
        let visible = window?.occlusionState.contains(.visible) == true && NSApp.isActive
        let animated = visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !ProcessInfo.processInfo.arguments.contains("--visual-test")
        var delay: TimeInterval = TimestampPolishSchedule.interval
        var pending = false
        for board in boards {
            var schedule = polishSchedules[board.kind] ?? TimestampPolishSchedule()
            if polishRevisions[board.kind] != board.polishRevision {
                schedule.update(now: now, ready: false)
                polishRevisions[board.kind] = board.polishRevision
            }
            let ready = animated && !showsSkeleton && board.polishReady && board.time.text != "—"
            schedule.update(now: now, ready: ready)
            polishSchedules[board.kind] = schedule
            if ready, let start = schedule.startedAt {
                pending = true
                delay = min(delay, schedule.phase(at: now) == nil ? max(0.02, start + TimestampPolishSchedule.interval - now) : 1 / 30)
            }
        }
        polishSchedules = polishSchedules.filter { key, _ in boards.contains { $0.kind == key } }
        needsDisplay = true
        if pending {
            polishTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePolish() }
            }
        }
    }

    /// Body capsules are the label composited at 35/255. Header titles drawn in
    /// `labelColor` are redacted as a solid block of that color instead, so the
    /// loading bar is near-black in light mode and near-white in dark mode.
    static let placeholderAlpha: CGFloat = 35.0 / 255.0

    static func requiredNameColumnWidth(title: String, licenseName: String?, summary: SourceLensDescription,
                                        time: (text: String, isSourceTime: Bool)) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titled = licenseName.map { title + " · " + $0 } ?? title
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: time.isSourceTime ? .semibold : .regular)
        let timeWidth = (time.text as NSString).size(withAttributes: [.font: timeFont]).width
        return ceil((titled as NSString).size(withAttributes: [
            .font: titleFont
        ]).width + ((summary.emphasis + " · ") as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10)
        ]).width + timeWidth + 18)
    }

    func configure(boards: [BoardHeaderConfiguration], language: AppLanguage,
        onOpennessFilter: ((LeaderboardKind, LeaderboardOpennessFilter) -> Void)?,
        onCountryFilter: ((LeaderboardKind, LeaderboardCountryFilter) -> Void)?, showsSkeleton: Bool) {
        self.boards = boards
        self.language = language
        self.onOpennessFilter = onOpennessFilter
        self.onCountryFilter = onCountryFilter
        self.showsSkeleton = showsSkeleton
        updatePolish()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard !showsSkeleton else { return }
        let point = convert(event.locationInWindow, from: nil)
        let column = column(at: point)
        if column > 0, (column - 1) % 4 == 0, boards.indices.contains((column - 1) / 4) {
            let board = boards[(column - 1) / 4]
            if timeRects[board.kind]?.contains(point) == true, let window {
                let alert = NSAlert()
                alert.messageText = LeaderboardPresentation.sourceTimeExplanationTitle(language: language)
                alert.informativeText = LeaderboardPresentation.sourceTimeExplanation(language: language)
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: window)
                return
            }
            if let window {
                let alert = NSAlert()
                alert.messageText = LeaderboardPresentation.columnTitle(board.kind, language: language)
                alert.informativeText = board.help + "\n\n" + board.kind.sourceURL.absoluteString
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: language.text("Copy link", "复制链接"))
                alert.beginSheetModal(for: window) { response in
                    if response == .alertSecondButtonReturn {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(board.kind.sourceURL.absoluteString, forType: .string)
                    }
                }
                return
            }
        }
        guard column > 0, boards.indices.contains((column - 1) / 4),
              [1, 2].contains((column - 1) % 4) else {
            super.mouseDown(with: event)
            return
        }
        let board = boards[(column - 1) / 4]
        if (column - 1) % 4 == 2 {
            menuKind = board.kind
            let selected = board.openness
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
        let selected = board.country
        menuChoices = board.countryOptions
        menuKind = board.kind
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

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !showsSkeleton else { return }
        for rect in timeRects.values { addCursorRect(rect, cursor: .pointingHand) }
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
        guard let tableView, tableView.tableColumns.count >= 5 else {
            super.draw(dirtyRect)
            return
        }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor(calibratedWhite: dark ? 0.14 : 0.97, alpha: 0.96).setFill()
        bounds.fill(using: .copy)

        timeRects.removeAll(keepingCapacity: true)
        for index in tableView.tableColumns.indices where !tableView.tableColumns[index].isHidden {
            let rect = headerRect(ofColumn: index)
            guard index > 0, boards.indices.contains((index - 1) / 4) else {
                tableView.tableColumns[index].headerCell.draw(withFrame: rect, in: self)
                continue
            }
            let board = boards[(index - 1) / 4]
            let role = (index - 1) % 4
            if showsSkeleton {
                if role == 0 { drawSkeletonNameHeader(tableView.tableColumns[index].headerCell.stringValue, in: rect) }
                else if role == 1 || role == 2 { drawSkeletonMark(in: rect, width: 28) }
                else { tableView.tableColumns[index].headerCell.draw(withFrame: rect, in: self) }
                continue
            }
            switch role {
            case 0:
                let tint = NSColor(Color(hex: SourceTabTheme.palette(for: board.kind, dark: dark).accent)!)
                drawBoardHeader(tableView.tableColumns[index].headerCell.stringValue,
                    licenseName: board.licenseName, summary: board.summary,
                    time: board.time, tint: tint,
                    polishPhase: board.polishReady ? (fixedPolishPhase ?? polishSchedules[board.kind]?.phase(at: ProcessInfo.processInfo.systemUptime)) : nil,
                    in: rect, kind: board.kind)
            case 1: drawCountryHeader(selected: board.country, in: rect)
            case 2: drawFilterHeader(title: ModelOpenness.columnTitle(language: language), active: board.openness != .all, in: rect)
            default: tableView.tableColumns[index].headerCell.draw(withFrame: rect, in: self)
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.height - 1 : 0, width: bounds.width, height: 1).fill()
        window?.invalidateCursorRects(for: self)
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
        let font = NSFont.systemFont(ofSize: 9.5, weight: active ? .semibold : .medium)
        let tint = NSColor.labelColor
        if active {
            let size = (title as NSString).size(withAttributes: [.font: font])
            let width = ceil(size.width) + 16
            let badge = NSRect(x: rect.midX - width / 2, y: rect.midY - 9, width: width, height: 18)
            (title as NSString).draw(at: NSPoint(x: badge.minX + 3, y: rect.midY - size.height / 2),
                withAttributes: [.font: font, .foregroundColor: tint])
            let icon = NSBezierPath()
            let x = badge.maxX - 10, y = rect.midY - 3.5
            func point(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint {
                NSPoint(x: x + dx, y: isFlipped ? y + dy : rect.midY + 3.5 - dy)
            }
            icon.move(to: point(1, 1)); icon.line(to: point(7, 1))
            icon.line(to: point(4.8, 3.8)); icon.line(to: point(4.8, 6))
            icon.line(to: point(3.2, 7)); icon.line(to: point(3.2, 3.8)); icon.close()
            icon.lineWidth = 0.9; icon.lineJoinStyle = .round; tint.setStroke(); icon.stroke()
            return
        }
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
        licenseName: String?,
        summary: SourceLensDescription,
        time: (text: String, isSourceTime: Bool),
        tint: NSColor,
        polishPhase: Double?,
        in rect: NSRect,
        kind: LeaderboardKind
    ) {
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: time.isSourceTime ? .semibold : .regular)
        let timeAttributes: [NSAttributedString.Key: Any] = [.font: timeFont,
            .foregroundColor: time.isSourceTime ? tint : NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue]
        let timeSize = (time.text as NSString).size(withAttributes: timeAttributes)
        let timeWidth = ceil(timeSize.width)
        let titleRect = NSTableHeaderCell(textCell: "").titleRect(forBounds: rect)
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let compactTitle = title.replacingOccurrences(of: "Artificial Analysis", with: "AA")
        let compactTitleWidth = (compactTitle as NSString).size(withAttributes: [.font: titleFont]).width
        // Narrow three-board views must retain the source identity. The lower
        // line still contains just one selected timestamp, never both dates.
        let stacked = rect.width < min(45, compactTitleWidth) + timeWidth + 18
        let timeY = stacked ? (isFlipped ? rect.maxY - timeSize.height - 3 : rect.minY + 3)
            : titleRect.midY - timeSize.height / 2
        let timeOrigin = NSPoint(x: rect.maxX - timeSize.width - 5, y: timeY)
        timeRects[kind] = NSRect(origin: timeOrigin, size: timeSize).insetBy(dx: -3, dy: -3).intersection(rect)
        (time.text as NSString).draw(at: timeOrigin, withAttributes: timeAttributes)
        if let polishPhase, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clip(to: NSRect(origin: timeOrigin, size: timeSize))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            (time.text as NSString).draw(at: timeOrigin, withAttributes: [.font: timeFont, .foregroundColor: NSColor.white])
            context.setBlendMode(.sourceIn)
            let colors = [NSColor.white.withAlphaComponent(0).cgColor,
                          NSColor.white.withAlphaComponent(0.85).cgColor,
                          NSColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                let x = timeOrigin.x + timeSize.width * (-0.45 + polishPhase * 1.45)
                context.drawLinearGradient(gradient, start: CGPoint(x: x, y: timeY),
                    end: CGPoint(x: x + timeSize.width * 0.45, y: timeY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
        let nameRect = NSRect(x: rect.minX, y: rect.minY, width: stacked ? rect.width : max(0, rect.width - timeWidth - 8), height: rect.height)
        let summaryFont = NSFont.systemFont(ofSize: 10)
        let available = max(0, nameRect.width - 10)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let explanation = NSAttributedString(string: summary.emphasis + " · ",
            attributes: [.font: summaryFont, .foregroundColor: tint])
        // Keep the introduction first while retaining the source in narrow columns.
        let visibleTitle = explanation.size().width + titleWidth > available ? compactTitle : title
        let text = NSMutableAttributedString(string: visibleTitle, attributes: [
            .font: titleFont, .foregroundColor: tint
        ])
        if explanation.size().width + text.size().width <= available {
            text.insert(explanation, at: 0)
        }
        let license = licenseName.map { " · " + $0 }
        let licenseWidth = license.map { ($0 as NSString).size(withAttributes: [.font: titleFont]).width } ?? 0
        let showsLicense = license != nil && text.size().width + licenseWidth <= available
        if showsLicense, let license {
            text.append(NSAttributedString(string: license, attributes: [
                .font: titleFont, .foregroundColor: tint
            ]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        let nameY = stacked ? (isFlipped ? rect.minY + 3 : rect.maxY - text.size().height - 3)
            : titleRect.midY - text.size().height / 2
        text.draw(in: NSRect(x: nameRect.minX + 5, y: nameY,
            width: available, height: ceil(text.size().height)))
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
    let cells: [LeaderboardCellModel?]
    var isDistribution = false
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
    var showRelativeShare: Bool = true
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
    let shareColor: Color
    let columnWidth: CGFloat
    /// Nil for skeleton placeholders, which must not be copied.
    let onSelectName: ((LeaderboardEntry) -> Bool)?

    private var entry: LeaderboardEntry? { model?.entry }

    // Reserve the same gutter for every row so the colored bars keep one scale.
    private static let shareGap: CGFloat = 4
    private static let shareWidth = ceil(("99%" as NSString).size(withAttributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
    ]).width)

    var body: some View {
        if entry == nil {
            nameContent()
        } else {
            // TableColumn has an exact width. Measuring it again in every
            // recycled cell adds two GeometryReader layout passes per model.
            let trackWidth = max(0, columnWidth - Self.shareWidth - Self.shareGap)
            let filledWidth = trackWidth * LeaderboardPresentation.scoreFillRatio(
                model?.entry.score ?? 0, leaderScore: model?.leaderScore)
            let share = LeaderboardPresentation.scoreShareText(
                model?.entry.score ?? 0, leaderScore: model?.leaderScore)
            let showsShare = model?.showRelativeShare != false && !share.isEmpty && filledWidth >= 38
            ZStack(alignment: .leading) {
                if let brandColor = model?.brandColor(isDark: colorScheme == .dark) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(brandColor.opacity(0.34))
                        .frame(width: filledWidth, height: 24)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                // Only the model column bounds the name; the score fill is background.
                nameContent(compact: trackWidth < 90)
                    .frame(width: trackWidth,
                           height: 24)
                if showsShare {
                    Text(share)
                        .font(.system(size: 8)).monospacedDigit()
                        .foregroundStyle(shareColor)
                        .fixedSize()
                        .frame(width: Self.shareWidth, alignment: .leading)
                        .position(x: trackWidth + Self.shareGap + Self.shareWidth / 2,
                                  y: 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: columnWidth, height: 24, alignment: .leading)
            .clipped()
        }
    }

    private func nameContent(compact: Bool = false) -> some View {
        HStack(spacing: compact ? 4 : 10) {
            if let entry {
                ModelLogoView(
                    url: model?.logoURL,
                    pngData: OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: model?.isCompany == true),
                    organization: entry.organization,
                    name: entry.name
                )
                modelName(entry, compact: compact)
                if model?.isCompany == true {
                    InlinePurchaseLinks(organization: entry.organization, modelName: entry.name, language: language)
                }
            } else {
                Text("-")
            }
        }
        .padding(.horizontal, compact ? 3 : 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: entry == nil ? .center : .leading)
        .clipped()
    }

    @ViewBuilder
    private func modelName(_ entry: LeaderboardEntry, compact: Bool) -> some View {
        if onSelectName != nil {
            CopyableModelName(
                name: entry.name,
                truncation: compact ? .tail : .middle,
                help: copyHelpText,
                accessibilityLabel: copyAccessibilityLabel(entry),
                onCopy: { onSelectName?(entry) ?? false }
            )
        } else if let help = nameHelpText {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(compact ? .tail : .middle)
                .help(help)
        } else {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(compact ? .tail : .middle)
        }
    }

    /// Full name stays in the tooltip when the visible name is truncated.
    private var copyHelpText: String {
        var lines: [String] = []
        if let name = entry?.name, !name.isEmpty {
            lines.append(name)
        }
        lines.append(model?.isCompany == true ? language.text("Click to copy", "点击复制") : language.text("View model details", "查看模型详情"))
        if let scoreHelp = model?.scoreHelp {
            lines.append(scoreHelp)
        }
        return lines.joined(separator: "\n")
    }

    private func copyAccessibilityLabel(_ entry: LeaderboardEntry) -> String {
        entry.name + (model?.isCompany == true ? language.text(", click to copy", "，点击复制") : language.text(", view model details", "，查看模型详情"))
    }

    private var nameHelpText: String? {
        model?.scoreHelp
    }

}

private struct OpennessCell: View {
    let model: LeaderboardCellModel?
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let openness = model?.entry.resolvedOpenness {
                ModelOpennessIcon(open: openness == .open)
                    .stroke(iconTint(openness), style: StrokeStyle(lineWidth: 14 / 12, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                    .accessibilityLabel(openness.title(language: language))
            } else {
                ModelOpennessBadge(nil, language: language, showsTitle: false, iconSize: 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .help(ModelOpenness.help(language: language))
    }

    private func iconTint(_ openness: ModelOpenness) -> Color {
        ModelOpennessBadge.tint(for: openness, dark: colorScheme == .dark)
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
    let kind: LeaderboardKind

    var body: some View {
        Group {
            if let entry = model?.entry {
                Text(LeaderboardPresentation.scoreText(entry.score, kind: kind))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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

@MainActor
private enum DesktopSegmentMetrics {
    static func width(labels: [String], regular: CGFloat, compact: Bool) -> CGFloat {
        guard compact else { return regular }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let labelWidth = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Equal segments fit the heaviest label plus eight points on each side.
        return ceil(labelWidth + 16) * CGFloat(labels.count)
    }
}

private struct CategorySegmentedControl: NSViewRepresentable {
    static let width: CGFloat = 420
    static let height: CGFloat = 24

    let language: AppLanguage
    var compact = false
    @Binding var selection: LeaderboardCategory

    private func label(_ category: LeaderboardCategory) -> String {
        switch category {
        case .general: language.text("General", "综合")
        case .coding: language.text("Coding", "编程")
        case .image: language.text("Image", "图片")
        case .video: language.text("Video", "视频")
        case .usage: language.text("Usage", "用量")
        }
    }

    private var controlWidth: CGFloat {
        DesktopSegmentMetrics.width(labels: LeaderboardCategory.allCases.map(label),
                                    regular: Self.width, compact: compact)
    }

    private func configureLabels(_ control: NSSegmentedControl) {
        for (index, category) in LeaderboardCategory.allCases.enumerated() {
            control.setLabel(label(category), forSegment: index)
            let width = controlWidth / CGFloat(LeaderboardCategory.allCases.count)
            if control.width(forSegment: index) != width { control.setWidth(width, forSegment: index) }
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
        CGSize(width: controlWidth, height: Self.height)
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
    var compact = false
    @Binding var selection: LeaderboardGrouping

    private func label(_ grouping: LeaderboardGrouping) -> String {
        switch grouping {
        case .model: language.text("Models", "模型")
        case .company: language.text("Companies", "公司")
        }
    }

    private var controlWidth: CGFloat {
        DesktopSegmentMetrics.width(labels: LeaderboardGrouping.allCases.map(label),
                                    regular: Self.width, compact: compact)
    }

    private func configureLabels(_ control: NSSegmentedControl) {
        for (index, grouping) in LeaderboardGrouping.allCases.enumerated() {
            control.setLabel(label(grouping), forSegment: index)
            let width = controlWidth / CGFloat(LeaderboardGrouping.allCases.count)
            if control.width(forSegment: index) != width { control.setWidth(width, forSegment: index) }
        }
        control.toolTip = language.text("Benchmark company scores use the strongest model; usage sums listed models.", "公司测评取最强模型分数；用量汇总榜内模型")
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
        CGSize(width: controlWidth, height: Self.height)
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
    var truncation: Text.TruncationMode = .middle
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
            .truncationMode(truncation)
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
    private var pointerTrackingArea: NSTrackingArea?

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
        // AppKit tracks .inVisibleRect as the clip bounds change. Replacing
        // this area on every scroll step only adds allocation/tracking work.
        guard pointerTrackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
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
        if let pngData, let image = ModelLogoImageCache.shared.image(data: pngData) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organization, modelName: name),
                  let image = ModelLogoImageCache.shared.bundledImage(key: key) {
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
