import SwiftUI
import LeaderboardCore

/// Screenshot toast state. `@State` is a SwiftUI macro, and Command Line Tools
/// do not ship the SwiftUIMacros plugin, so this stays an observable object.
@MainActor
private final class ScreenshotUIState: ObservableObject {
    @Published var note: String?
    @Published var noteID = 0
    @Published var isCapturing = false
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
    private static let tableChromeBaseWidth: CGFloat = 288
    private static let countryColumnWidth: CGFloat = 68

    let maximumWidth: CGFloat

    private var contentWidth: CGFloat {
        Self.preferredWidth(for: state, maximumWidth: maximumWidth)
    }

    private var contentHeight: CGFloat {
        Self.preferredHeight(for: state, width: contentWidth, maximumWidth: maximumWidth)
    }

    private var nameColumnWidth: CGFloat {
        (contentWidth - Self.tableChromeWidth) / 2
    }

    private static var tableChromeWidth: CGFloat {
        tableChromeBaseWidth + countryColumnWidth * 2
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
                        let entries = state.snapshot.boards[kind]?.entries ?? []
                        return grouping == .company
                            ? CompanyLeaderboard.rank(entries).map(\.entry)
                            : Array(entries.prefix(20))
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
        let desired = max(minimumWidth, ceil(max(columnWidth, headerWidth) * 2 + tableChromeWidth))
        return min(desired, maximumWidth)
    }

    static func preferredHeight(for state: AppState, width: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        let view = LeaderboardView(state: state, maximumWidth: maximumWidth)
        let header = NSHostingView(rootView: view.header.frame(width: width))
        let footer = NSHostingView(rootView: view.footer.frame(width: width))
        // Native header plus visible rows. A country filter can shorten the table.
        return ceil(header.fittingSize.height
            + 24 + CGFloat(visibleRowCount(for: state)) * 32
            + 1 + footer.fittingSize.height)
    }

    private static func visibleRowCount(for state: AppState) -> Int {
        let kinds = state.selectedCategory.boardKinds
        let raw = kinds.map { state.snapshot.boards[$0]?.entries ?? [] }
        if raw.allSatisfy(\.isEmpty) || kinds.allSatisfy({ state.countryFilters[$0] == nil }) {
            return 20
        }
        let counts = zip(kinds, raw).map { kind, entries in
            let filter = state.countryFilters[kind] ?? .all
            let matching = entries.filter(filter.matches)
            return state.selectedGrouping == .company
                ? CompanyLeaderboard.rank(matching).count : matching.count
        }
        return min(20, max(1, counts.max() ?? 0))
    }

    private static func boardColumnTitle(
        _ title: String,
        kind: LeaderboardKind,
        state: AppState
    ) -> String {
        guard let sourceDate = state.snapshot.boards[kind]?.sourceUpdatedAt else { return title }
        let formatter = DateFormatter()
        formatter.locale = state.selectedLanguage.locale
        formatter.dateFormat = "M/d HH:mm"
        return "\(title) · \(formatter.string(from: sourceDate))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Divider()
            footer
        }
        .frame(width: contentWidth, height: contentHeight)
        .background(.background)
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
                    onConnectQwen: state.connectQwenWebsite
                )
                .padding(.top, 10)
                .background(QuotaStripAnchor())
            } else if state.quotaNeedsCCSwitch {
                quotaSetupPrompt
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var quotaSetupPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(tr(
                "See provider quotas here with CC Switch.",
                "安装 CC Switch，即可在这里查看各家提供商的余量。"
            ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Link(
                tr("Download CC Switch", "下载 CC Switch"),
                destination: URL(string: "https://github.com/farion1231/cc-switch/releases/latest")!
            )
            .font(.system(size: 11, weight: .medium))
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceHeaderHelp(kind: LeaderboardKind, description: SourceLensDescription) -> String {
        var parts = [
            description.detail,
            tr("Scores are not directly comparable across lists", "两榜分数不直接互比"),
        ]
        if let board = state.snapshot.boards[kind] {
            if let sourceDate = board.sourceUpdatedAt {
                let formatter = DateFormatter()
                formatter.locale = language.locale
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let label = kind.sourcePrefix == "Arena"
                    ? tr("Votes through", "投票截至")
                    : tr("Updated", "更新于")
                parts.append("\(label) \(formatter.string(from: sourceDate))")
            }
            if let note = board.sourceNote, !note.isEmpty {
                parts.append(note)
            }
        }
        return parts.joined(separator: tr(". ", "。"))
    }

    @ViewBuilder
    private var titleRow: some View {
        if contentWidth < 1100 {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    appTitle
                    Spacer(minLength: 12)
                    freshness
                }
                HStack(spacing: 8) {
                    groupingPicker
                    categoryPicker
                }
            }
        } else {
            // Equal side columns keep the tabs centered on wider panels.
            HStack(alignment: .center, spacing: 12) {
                appTitle.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    groupingPicker
                    categoryPicker
                }
                freshness.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var appTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("AI Leaderboards")
                // Snell Roundhand ships with macOS, so referencing it by
                // name needs no font bundling or license.
                .font(.custom("SnellRoundhand-Bold", size: 21))
                .lineLimit(1)
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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

    private var selectedCategory: LeaderboardCategory {
        state.selectedCategory
    }

    /// One heading identifies both timestamps; the hairline separates the
    /// leaderboard data from this Mac's quota data.
    private func freshnessLine(now: Date) -> some View {
        HStack(spacing: 8) {
            Text(tr("UPDATED", "更新时间"))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            // Shrinking would break the equal-width guarantee, so both values
            // keep their natural size.
            Text(rankingClause(now: now, format: .stamp))
                .foregroundStyle(rankingFailed ? Color.orange : Color.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let quota = quotaClause(now: now, format: .stamp) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 9)
                    .accessibilityHidden(true)
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

    /// The group is right-aligned, so any change in the value's width pushes
    /// the "更新时间" heading sideways. Reserving a frame instead would leave a
    /// hole whenever the copy is short. A fixed-shape timestamp avoids both:
    /// `HH:mm` in tabular digits measures the same for every value, so the
    /// heading stays put and nothing is reserved. `.relative` keeps the
    /// friendlier phrasing for the tooltip and VoiceOver, where width is free.
    private enum FreshnessFormat {
        case stamp
        case relative
    }

    private func freshnessValue(_ date: Date, now: Date, format: FreshnessFormat) -> String {
        switch format {
        case .stamp: clockStamp(date, now: now)
        case .relative: updateAge(date, now: now)
        }
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
        guard let fetchedAt else { return tr("Rankings pending", "榜单待更新") }
        let value = freshnessValue(fetchedAt, now: now, format: format)
        return tr("Rankings \(value)", "榜单 \(value)")
    }

    private func updateAge(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return tr("just now", "刚刚") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return tr("\(minutes) min ago", "\(minutes) 分钟前") }
        let hours = Int(seconds / 3600)
        if hours < 24 { return tr("\(hours) hr ago", "\(hours) 小时前") }
        let days = Int(seconds / 86_400)
        return tr("\(days) \(days == 1 ? "day" : "days") ago", "\(days) 天前")
    }

    private var rankingFailed: Bool {
        !state.isRefreshing && !state.lastErrors.isEmpty
    }

    private func freshnessSummary(now: Date) -> String {
        var summary = tr("Last updated: ", "更新时间：")
            + rankingClause(now: now, format: .relative)
        if let quota = quotaClause(now: now, format: .relative) {
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
        } else if quotaClause(now: now) != nil {
            parts.append(tr("Quota comes from this Mac's CC Switch data", "余量来自本机 CC Switch。没安装或读不懂配置时不显示，也不需要安装 Codex"))
        }
        return parts.joined(separator: tr(". ", "。"))
    }

    private func quotaClause(now: Date) -> String? {
        if state.quotaChips.isEmpty {
            return state.quotaUnavailable ? tr("Quota unavailable", "余量暂不可读") : nil
        }
        guard let updatedAt = state.quotaUpdatedAt else { return tr("Quota pending", "余量待更新") }
        return tr("Quota \(updateAge(updatedAt, now: now))", "余量 \(updateAge(updatedAt, now: now))")
    }

    // Both name columns grow with the longest visible name. The country and
    // score columns stay aligned across rows and both halves of the table.
    private var table: some View {
        let lenses = selectedCategory.sourceLenses(language: language)
        return Table(rows) {
            TableColumn(tr("Rank", "排名")) { row in
                Text(rankLabel(row.rank))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(48)
            .alignment(.center)

            TableColumn(Self.boardColumnTitle(
                selectedCategory.leftColumnTitle,
                kind: selectedCategory.leftKind,
                state: state
            )) { row in
                LeaderboardCell(model: row.left, language: language, onCopyName: nameCopyAction)
            }
            .width(nameColumnWidth)

            TableColumn(tr("Score", "分数")) { row in
                ScoreCell(model: row.left, scoreDigits: 1)
            }
            .width(60)
            .alignment(.center)

            TableColumn(tr("Country", "国家")) { row in
                CountryCell(model: row.left, language: language)
            }
            .width(Self.countryColumnWidth)
            .alignment(.center)

            TableColumn(Self.boardColumnTitle(
                selectedCategory.rightColumnTitle,
                kind: selectedCategory.rightKind,
                state: state
            )) { row in
                LeaderboardCell(model: row.right, language: language, onCopyName: nameCopyAction)
            }
            .width(nameColumnWidth)

            TableColumn(tr("Score", "分数")) { row in
                ScoreCell(model: row.right, scoreDigits: 1)
            }
            .width(60)
            .alignment(.center)

            TableColumn(tr("Country", "国家")) { row in
                CountryCell(model: row.right, language: language)
            }
            .width(Self.countryColumnWidth)
            .alignment(.center)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .scrollIndicators(.hidden)
        .background(TableChrome(
            left: lenses.aa,
            right: lenses.arena,
            leftHelp: selectedCategory.leftColumnTitle + tr(". ", "。")
                + sourceHeaderHelp(kind: selectedCategory.leftKind, description: lenses.aa),
            rightHelp: selectedCategory.rightColumnTitle + tr(". ", "。")
                + sourceHeaderHelp(kind: selectedCategory.rightKind, description: lenses.arena),
            leftKind: selectedCategory.leftKind,
            rightKind: selectedCategory.rightKind,
            language: language,
            leftFilter: state.countryFilters[selectedCategory.leftKind] ?? .all,
            rightFilter: state.countryFilters[selectedCategory.rightKind] ?? .all,
            leftCountryOptions: countryOptions(for: selectedCategory.leftKind),
            rightCountryOptions: countryOptions(for: selectedCategory.rightKind),
            onCountryFilter: { kind, filter in
                state.selectCountryFilter(filter, for: kind)
            }
        ))
        .id(contentWidth)
        .redacted(reason: needsSkeleton ? .placeholder : [])
        .disabled(needsSkeleton)
    }

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 1: "🥇"
        case 2: "🥈"
        case 3: "🥉"
        default: "\(rank)"
        }
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

    private let repositoryURL = "https://github.com/cloydlau/ai-leaderboard-menubar"

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
            let content = quotaSetupPrompt
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
        guard let shot = PanelScreenshot.capture(view: view, replacingTopBandWith: replacement) else {
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
        HStack(spacing: 7) {
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
            Text("MIT License")

            Spacer()

            Text(tr("Sources", "数据来源"))
            sourceLink(
                title: selectedCategory.leftKind.sourceLinkTitle,
                url: selectedCategory.leftKind.sourceURL.absoluteString
            )
            Text("·")
            sourceLink(
                title: selectedCategory.rightKind.sourceLinkTitle,
                url: selectedCategory.rightKind.sourceURL.absoluteString
            )

            Text("·")

            Button {
                captureScreenshot()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .imageScale(.small)
                    Text(tr("Screenshot", "截图"))
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor(isEnabled: !state.isQuitting && !screenshot.isCapturing)
            .allowsHitTesting(!state.isQuitting && !screenshot.isCapturing)
            .help(tr("Copy a screenshot with the CC Switch quota guide", "复制显示 CC Switch 余量引导的截图"))

            Text("·")

            Toggle(tr("Close on blur", "失焦关闭"), isOn: Binding(
                get: { state.closesOnFocusLoss },
                set: { state.setClosesOnFocusLoss($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))
            .fixedSize()
            .help(tr(
                "Close the panel when clicking outside or switching apps.",
                "点击弹窗外或切换应用时关闭弹窗。"
            ))

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
            .frame(width: 150)
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
                        Text(tr("Quitting", "退出中"))
                    } else {
                        Image(systemName: "power")
                            .imageScale(.small)
                        Text(tr("Quit", "退出"))
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor(isEnabled: !state.isQuitting)
            .allowsHitTesting(!state.isQuitting)
            .help(state.isQuitting ? tr("Quitting AI Leaderboards", "正在退出 AI Leaderboards") : tr("Quit AI Leaderboards", "退出 AI Leaderboards"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
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
        let rightEmpty = state.snapshot.boards[selectedCategory.rightKind]?.entries.isEmpty ?? true
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
        let right = displayedEntries(kind: selectedCategory.rightKind)
        let organizationLogos = self.organizationLogos

        return (0..<Self.visibleRowCount(for: state)).map { index in
            LeaderboardRow(
                rank: index + 1,
                left: cellModel(
                    for: index < left.count ? left[index] : nil,
                    organizationLogos: organizationLogos
                ),
                right: cellModel(
                    for: index < right.count ? right[index] : nil,
                    organizationLogos: organizationLogos
                )
            )
        }
    }

    /// Company rows are derived here, from models already on the board.
    /// Fewer than 20 companies keep the existing dash slots.
    private func displayedEntries(kind: LeaderboardKind) -> [DisplayedLeaderboardEntry] {
        let filter = state.countryFilters[kind] ?? .all
        let entries = (state.snapshot.boards[kind]?.entries ?? []).filter(filter.matches)
        guard state.selectedGrouping == .company else {
            return entries.map {
                DisplayedLeaderboardEntry(entry: $0, scoreHelp: nil, isCompany: false)
            }
        }
        return CompanyLeaderboard.rank(entries).map { standing in
            DisplayedLeaderboardEntry(
                entry: standing.entry,
                scoreHelp: CompanyLeaderboard.scoreHelp(for: standing, language: language),
                isCompany: true
            )
        }
    }

    private func countryOptions(for kind: LeaderboardKind) -> [CountryFilter] {
        let entries = state.snapshot.boards[kind]?.entries ?? []
        let countries = entries.map {
            OrganizationRegion.country($0.organization, modelName: $0.name)
        }
        let codes = Set(countries.compactMap { $0?.rawValue })
        var options: [CountryFilter] = [.all]
        options += OrganizationCountry.allCases
            .filter { codes.contains($0.rawValue) }
            .map(CountryFilter.country)
        if countries.contains(where: { $0 == nil }) {
            options.append(.unknown)
        }
        return options
    }

    private func cellModel(
        for displayed: DisplayedLeaderboardEntry?,
        organizationLogos: [String: URL]
    ) -> LeaderboardCellModel? {
        guard let displayed else { return nil }
        let entry = displayed.entry
        let key = OrganizationLogoCatalog.resolvedKey(
            organization: entry.organization,
            modelName: entry.name
        )
        return LeaderboardCellModel(
            entry: entry,
            brandHex: OrganizationLogoCatalog.brandColorHex(
                forOrganization: entry.organization,
                modelName: entry.name
            ),
            logoURL: entry.logoURL
                ?? key.flatMap { organizationLogos[$0] }
                ?? OrganizationLogoCatalog.logoURL(
                    forOrganization: entry.organization,
                    modelName: entry.name
                ),
            scoreHelp: displayed.scoreHelp,
            isCompany: displayed.isCompany
        )
    }

    private var organizationLogos: [String: URL] {
        var logos: [String: URL] = [:]
        for kind in [selectedCategory.leftKind, selectedCategory.rightKind] {
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

enum CountryFilter: Equatable {
    case all
    case country(OrganizationCountry)
    case unknown

    func matches(_ entry: LeaderboardEntry) -> Bool {
        let country = OrganizationRegion.country(entry.organization, modelName: entry.name)
        switch self {
        case .all: return true
        case .country(let selected): return country == selected
        case .unknown: return country == nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all: return language.text("All countries", "全部国家")
        case .country(let country): return "\(country.flagEmoji)  \(country.localizedName(language: language))"
        case .unknown: return language.text("Unknown country", "国家未知")
        }
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
    let leftFilter: CountryFilter
    let rightFilter: CountryFilter
    let leftCountryOptions: [CountryFilter]
    let rightCountryOptions: [CountryFilter]
    let onCountryFilter: (LeaderboardKind, CountryFilter) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.configure(
            left: left, right: right, leftHelp: leftHelp, rightHelp: rightHelp,
            leftKind: leftKind, rightKind: rightKind,
            language: language, leftFilter: leftFilter, rightFilter: rightFilter,
            leftCountryOptions: leftCountryOptions, rightCountryOptions: rightCountryOptions,
            onCountryFilter: onCountryFilter
        )
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.configure(
            left: left, right: right, leftHelp: leftHelp, rightHelp: rightHelp,
            leftKind: leftKind, rightKind: rightKind,
            language: language, leftFilter: leftFilter, rightFilter: rightFilter,
            leftCountryOptions: leftCountryOptions, rightCountryOptions: rightCountryOptions,
            onCountryFilter: onCountryFilter
        )
    }

    final class ProbeView: NSView {
        private var left = SourceLensDescription(emphasis: "", detail: "")
        private var right = SourceLensDescription(emphasis: "", detail: "")
        private var leftHelp = ""
        private var rightHelp = ""
        private var leftKind: LeaderboardKind?
        private var rightKind: LeaderboardKind?
        private var language = AppLanguage.english
        private var leftFilter = CountryFilter.all
        private var rightFilter = CountryFilter.all
        private var leftCountryOptions: [CountryFilter] = []
        private var rightCountryOptions: [CountryFilter] = []
        private var onCountryFilter: ((LeaderboardKind, CountryFilter) -> Void)?

        func configure(
            left: SourceLensDescription,
            right: SourceLensDescription,
            leftHelp: String,
            rightHelp: String,
            leftKind: LeaderboardKind,
            rightKind: LeaderboardKind,
            language: AppLanguage,
            leftFilter: CountryFilter,
            rightFilter: CountryFilter,
            leftCountryOptions: [CountryFilter],
            rightCountryOptions: [CountryFilter],
            onCountryFilter: @escaping (LeaderboardKind, CountryFilter) -> Void
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
            self.onCountryFilter = onCountryFilter
            updateTable()
        }

        override func layout() {
            super.layout()
            updateTable()
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
                if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
                if scrollView.horizontalScrollElasticity != .none {
                    scrollView.horizontalScrollElasticity = .none
                }
                if let tableView = Self.findTable(in: scrollView.documentView),
                   tableView.tableColumns.count >= 7 {
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
                onCountryFilter: onCountryFilter
            )
            tableView.tableColumns[1].headerToolTip = leftHelp
            tableView.tableColumns[4].headerToolTip = rightHelp
            let filterHelp = language.text("Filter by country", "按国家筛选")
            tableView.tableColumns[3].headerToolTip = filterHelp
            tableView.tableColumns[6].headerToolTip = filterHelp
        }
    }
}

private final class SourceTableHeaderView: NSTableHeaderView {
    static let height: CGFloat = 24
    private var left = SourceLensDescription(emphasis: "", detail: "")
    private var right = SourceLensDescription(emphasis: "", detail: "")
    private var language = AppLanguage.english
    private var leftKind: LeaderboardKind?
    private var rightKind: LeaderboardKind?
    private var leftFilter = CountryFilter.all
    private var rightFilter = CountryFilter.all
    private var leftCountryOptions: [CountryFilter] = []
    private var rightCountryOptions: [CountryFilter] = []
    private var onCountryFilter: ((LeaderboardKind, CountryFilter) -> Void)?
    private var menuChoices: [CountryFilter] = []
    private var menuKind: LeaderboardKind?

    static func requiredNameColumnWidth(title: String, summary: SourceLensDescription) -> CGFloat {
        ceil(headerText(
            title: title, summary: summary, tint: .systemBlue,
            titleSize: 11, descriptionSize: 10
        ).size().width + 10)
    }

    func configure(
        left: SourceLensDescription,
        right: SourceLensDescription,
        language: AppLanguage,
        leftKind: LeaderboardKind?,
        rightKind: LeaderboardKind?,
        leftFilter: CountryFilter,
        rightFilter: CountryFilter,
        leftCountryOptions: [CountryFilter],
        rightCountryOptions: [CountryFilter],
        onCountryFilter: ((LeaderboardKind, CountryFilter) -> Void)?
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
        self.onCountryFilter = onCountryFilter
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = column(at: point)
        guard column == 3 || column == 6 else {
            super.mouseDown(with: event)
            return
        }
        let kind = column == 3 ? leftKind : rightKind
        guard let kind else { return }
        let selected = column == 3 ? leftFilter : rightFilter
        menuChoices = column == 3 ? leftCountryOptions : rightCountryOptions
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

    @objc private func selectCountry(_ sender: NSMenuItem) {
        guard let menuKind, menuChoices.indices.contains(sender.tag) else { return }
        onCountryFilter?(menuKind, menuChoices[sender.tag])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tableView, tableView.tableColumns.count >= 7 else {
            super.draw(dirtyRect)
            return
        }
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        for index in tableView.tableColumns.indices {
            let columnRect = headerRect(ofColumn: index)
            switch index {
            case 1:
                drawBoardHeader(
                    tableView.tableColumns[index].headerCell.stringValue,
                    summary: left,
                    tint: .systemBlue,
                    in: columnRect
                )
            case 4:
                drawBoardHeader(
                    tableView.tableColumns[index].headerCell.stringValue,
                    summary: right,
                    tint: .systemPurple,
                    in: columnRect
                )
            case 3, 6:
                drawCountryHeader(
                    selected: index == 3 ? leftFilter : rightFilter,
                    in: columnRect
                )
            default:
                tableView.tableColumns[index].headerCell.draw(withFrame: columnRect, in: self)
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.height - 1 : 0, width: bounds.width, height: 1).fill()
    }

    /// The label stays on the column centre shared with the flags below, and
    /// the filter caret is stroked separately on the label's midline: an
    /// inline "⌄" rides the text baseline and reads as too low.
    private func drawCountryHeader(selected: CountryFilter, in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let tint = selected == .all ? NSColor.labelColor : NSColor.controlAccentColor
        let title = language.text("Country", "国家")
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
        let halfWidth: CGFloat = 3
        let halfHeight: CGFloat = 1.6
        let gap: CGFloat = 3
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
        // Use the same native header cell drawing as Rank, Score and Country.
        // It places the entire attributed line on their shared vertical center.
        let cell = NSTableHeaderCell(textCell: "")
        cell.alignment = .left
        cell.lineBreakMode = .byTruncatingTail
        let availableWidth = max(0, cell.titleRect(forBounds: rect).width)
        let sizePairs: [(CGFloat, CGFloat)] = [
            (11, 10), (11, 9), (11, 8),
            (10.5, 8), (10, 8), (9.5, 8), (9, 8),
            (8.5, 7.5),
        ]
        var text = NSAttributedString()
        for (titleSize, descriptionSize) in sizePairs {
            let candidate = Self.headerText(
                title: title, summary: summary, tint: tint,
                titleSize: titleSize, descriptionSize: descriptionSize
            )
            text = candidate
            if candidate.size().width <= availableWidth { break }
        }
        cell.attributedStringValue = text
        cell.draw(withFrame: rect, in: self)
    }

    private static func headerText(
        title: String,
        summary: SourceLensDescription,
        tint: NSColor,
        titleSize: CGFloat,
        descriptionSize: CGFloat
    ) -> NSAttributedString {
        let secondaryBaselineOffset = (titleSize - descriptionSize) / 2
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: titleSize, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        text.append(NSAttributedString(
            string: " · ",
            attributes: [
                .font: NSFont.systemFont(ofSize: descriptionSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .baselineOffset: secondaryBaselineOffset,
            ]
        ))
        text.append(NSAttributedString(
            string: summary.emphasis,
            attributes: [
                .font: NSFont.systemFont(ofSize: descriptionSize, weight: .semibold),
                .foregroundColor: tint,
                .baselineOffset: secondaryBaselineOffset,
            ]
        ))
        text.append(NSAttributedString(
            string: " " + summary.detail,
            attributes: [
                .font: NSFont.systemFont(ofSize: descriptionSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .baselineOffset: secondaryBaselineOffset,
            ]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(
            location: 0, length: text.length
        ))
        return text
    }
}

private extension LeaderboardCategory {
    var leftKind: LeaderboardKind { boardKinds[0] }
    var rightKind: LeaderboardKind { boardKinds[1] }

    var leftColumnTitle: String {
        switch self {
        case .general: "Artificial Analysis Intelligence Index"
        case .coding: "Artificial Analysis Coding Agent Index"
        case .image: "Artificial Analysis | 文生图"
        case .video: "Artificial Analysis | 文生视频"
        }
    }

    var rightColumnTitle: String {
        switch self {
        case .general: "Arena | Text"
        case .coding: "Code Arena | WebDev"
        case .image: "Arena | 文生图"
        case .video: "Arena | 文生视频"
        }
    }

    /// AA's language/coding indexes use task benchmarks; its image/video
    /// boards also use human votes, but with curated prompts or matched settings.
    /// Arena ratings come from blind user comparisons across the categories.
    func sourceLenses(language: AppLanguage) -> (aa: SourceLensDescription, arena: SourceLensDescription) {
        switch self {
        case .general:
            return (
                SourceLensDescription(
                    emphasis: language.text("Task benchmarks", "任务测评"),
                    detail: language.text(
                        "Combines standardized tests across several abilities.",
                        "汇总多项标准化测试，适合看综合能力"
                    )
                ),
                SourceLensDescription(
                    emphasis: language.text("User votes", "用户盲测"),
                    detail: language.text(
                        "People compare anonymous answers to real prompts.",
                        "真实提问下盲选回答，贴近用户偏好"
                    )
                )
            )
        case .coding:
            return (
                SourceLensDescription(
                    emphasis: language.text("Task completion", "任务完成率"),
                    detail: language.text(
                        "Scores coding agents on software engineering tasks.",
                        "通过软件工程任务，检验编程智能体的完成能力"
                    )
                ),
                SourceLensDescription(
                    emphasis: language.text("WebDev votes", "网页开发盲选"),
                    detail: language.text(
                        "People pick the better result from paired web builds.",
                        "用户盲选网页成品，侧重实际观感"
                    )
                )
            )
        case .image:
            return (
                SourceLensDescription(
                    emphasis: language.text("Curated prompts", "场景化盲测"),
                    detail: language.text(
                        "Blind votes across a balanced set of image use cases.",
                        "按用途均衡选题，盲选图片质量"
                    )
                ),
                SourceLensDescription(
                    emphasis: language.text("User prompts", "用户出题"),
                    detail: language.text(
                        "People vote on images made from their own prompts.",
                        "用户自由出题并盲选，贴近日常审美"
                    )
                )
            )
        case .video:
            return (
                SourceLensDescription(
                    emphasis: language.text("Matched settings", "统一设置"),
                    detail: language.text(
                        "Blind votes on videos made with comparable settings.",
                        "相同提示词、统一设置下盲选视频质量"
                    )
                ),
                SourceLensDescription(
                    emphasis: language.text("User prompts", "用户出题"),
                    detail: language.text(
                        "People vote on paired videos from real prompts.",
                        "用户自由出题并盲选，贴近日常偏好"
                    )
                )
            )
        }
    }
}

private struct SourceLensDescription {
    let emphasis: String
    let detail: String
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(brandColor.opacity(0.34))
            }
        }
    }
}

private struct CountryCell: View {
    let model: LeaderboardCellModel?
    let language: AppLanguage

    private var country: OrganizationCountry? {
        OrganizationRegion.country(model?.entry.organization, modelName: model?.entry.name)
    }

    var body: some View {
        Text(country?.flagEmoji ?? "-")
            .font(.system(size: 17))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
            .modifier(OptionalHelp(text: country?.localizedName(language: language)))
            .accessibilityLabel(country?.localizedName(language: language)
                                ?? language.text("Country unknown", "国家未知"))
    }
}

private struct ScoreCell: View {
    let model: LeaderboardCellModel?
    let scoreDigits: Int

    var body: some View {
        Group {
            if let entry = model?.entry {
                Text(entry.score.formatted(.number.precision(.fractionLength(scoreDigits))))
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

    final class Coordinator: NSObject {
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

    final class Coordinator: NSObject {
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
    let organization: String?
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
            logoContent
                .padding(2.5)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var logoContent: some View {
        if let bundled = bundledLogoURL, let image = NSImage(contentsOf: bundled) {
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
        Text(String((organization ?? name).prefix(1)).uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
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
