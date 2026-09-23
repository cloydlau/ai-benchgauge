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
    @ObservedObject var state: AppState
    @StateObject private var screenshot = ScreenshotUIState()

    static let contentWidth: CGFloat = 1300
    static let contentHeight: CGFloat = 866

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Divider()
            footer
        }
        .frame(width: Self.contentWidth, height: Self.contentHeight)
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
                Text("正在退出…")
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
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            VStack(alignment: .leading, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    freshnessLine(now: context.date)
                }
                if !state.quotaChips.isEmpty {
                    QuotaStrip(
                        chips: state.quotaChips,
                        onConnectQwen: state.connectQwenWebsite
                    )
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var titleRow: some View {
        // Equal side columns keep the tabs centered. A trailing spacer left a
        // wide empty band between the title and the picker. Grouping sits
        // beside the category control; both widths are fixed so 公司 does not
        // reflow the table columns. Freshness is its own row, not a corner of this one.
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AI Leaderboards")
                    .font(.system(size: 17, weight: .semibold))
                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                groupingPicker
                categoryPicker
            }

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
                .accessibilityHidden(true)
        }
        .animation(nil, value: state.selectedCategory)
        .animation(nil, value: state.selectedGrouping)
    }

    private var groupingPicker: some View {
        GroupingSegmentedControl(
            selection: Binding(
                get: { state.selectedGrouping },
                set: { state.selectGrouping($0) }
            )
        )
        .frame(width: GroupingSegmentedControl.width, height: GroupingSegmentedControl.height)
        .help("按公司查看时，以最强模型分数为准，弱型号不拉低")
    }

    private var categoryPicker: some View {
        CategorySegmentedControl(
            selection: Binding(
                get: { state.selectedCategory },
                set: { state.selectCategory($0) }
            )
        )
        .frame(width: CategorySegmentedControl.width, height: CategorySegmentedControl.height)
        .help("切换榜单类别")
    }

    private var selectedCategory: LeaderboardCategory {
        state.selectedCategory
    }

    /// One caption for every freshness fact. They used to sit in three places:
    /// under the title, at the trailing edge, and beside the quota chips.
    private func freshnessLine(now: Date) -> some View {
        freshnessText(now: now)
            .font(.system(size: 11))
            .monospacedDigit()
            .lineLimit(1)
            .help(freshnessHelp(now: now))
    }

    private func freshnessText(now: Date) -> Text {
        var text = leaderboardStatusText
        text = text + Text(" · ").foregroundStyle(.quaternary)
        text = text + Text(scheduleClause(now: now)).foregroundStyle(.secondary)
        if let quota = quotaClause(now: now) {
            text = text + Text(" · ").foregroundStyle(.quaternary)
            let tone: Color = state.quotaUnavailable ? .orange : .secondary
            text = text + Text(quota).foregroundStyle(tone)
        }
        return text
    }

    private var leaderboardStatusText: Text {
        if state.isRefreshing {
            return Text("更新中").foregroundStyle(.secondary)
        }
        if state.lastErrors.isEmpty {
            return Text("已更新").foregroundStyle(.secondary)
        }
        return Text("部分榜单更新失败").foregroundStyle(.orange)
    }

    private func freshnessHelp(now: Date) -> String {
        var parts: [String] = []
        if state.isRefreshing {
            parts.append("正在更新榜单")
        } else if state.lastErrors.isEmpty {
            parts.append("榜单已更新，每天 \(clockTime(state.schedule.dailyRunAt)) 自动更新")
        } else {
            parts.append("部分榜单更新失败，将按计划重试")
        }
        if state.quotaUnavailable && state.quotaChips.isEmpty {
            parts.append("这次没读成本机 CC Switch 数据库")
        } else if state.quotaUnavailable {
            parts.append("余量数据库这次没有读成，显示的是上次余量")
        } else if quotaClause(now: now) != nil {
            parts.append("余量来自本机 CC Switch。没安装或读不懂配置时不显示，也不需要安装 Codex")
        }
        return parts.joined(separator: "。")
    }

    private func scheduleClause(now: Date) -> String {
        if let retryAt = state.schedule.retryAfterFailureAt, retryAt < state.schedule.giveUpAt {
            return "下次重试 \(compactWhen(retryAt, now: now))"
        }
        let run = state.schedule.dailyRunAt
        if Calendar.current.isDateInToday(run) || Calendar.current.isDateInTomorrow(run) {
            return "每日 \(clockTime(run))"
        }
        return "每日 \(compactWhen(run, now: now))"
    }

    private func quotaClause(now: Date) -> String? {
        if state.quotaChips.isEmpty {
            return state.quotaUnavailable ? "CC Switch 暂不可读" : nil
        }
        if state.quotaUnavailable { return "余量未刷新" }
        guard let updatedAt = state.quotaUpdatedAt else { return "余量" }
        return "余量 \(relativeTime(updatedAt, now: now))"
    }

    private func relativeTime(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1)) 分钟前" }
        return compactWhen(date, now: now)
    }

    private func compactWhen(_ date: Date, now: Date) -> String {
        let time = clockTime(date)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        return "\(monthDay(date)) \(time)"
    }

    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // Longest names are about 420pt, before the logo and purchase links.
    // Score columns only need a value like 1800.3. Keep their max tight so the
    // native table gives leftover width to the model-name columns.
    private var table: some View {
        Table(rows) {
            TableColumn("排名") { row in
                Text(rankLabel(row.rank))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(min: 36, ideal: 42, max: 48)
            .alignment(.center)

            TableColumn(columnTitle(
                selectedCategory.leftColumnTitle,
                kind: selectedCategory.leftKind,
                preferSourceUpdatedAt: false
            )) { row in
                LeaderboardCell(model: row.left)
            }
            .width(min: 500, ideal: 560, max: 680)

            TableColumn("分数") { row in
                ScoreCell(model: row.left, scoreDigits: 1)
            }
            .width(min: 48, ideal: 56, max: 64)
            .alignment(.center)

            TableColumn(columnTitle(
                selectedCategory.rightColumnTitle,
                kind: selectedCategory.rightKind,
                preferSourceUpdatedAt: true
            )) { row in
                LeaderboardCell(model: row.right)
            }
            .width(min: 500, ideal: 560, max: 680)

            TableColumn("分数") { row in
                ScoreCell(model: row.right, scoreDigits: 1)
            }
            .width(min: 48, ideal: 56, max: 64)
            .alignment(.center)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
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

    /// Wait out the button highlight, and any toast fade, so neither is in the image.
    private func captureScreenshot() {
        guard !state.isQuitting, !screenshot.isCapturing else { return }
        screenshot.isCapturing = true
        let settle = screenshot.note == nil ? 80 : 220
        // Invalidate a pending dismiss so it cannot clear the result toast.
        screenshot.noteID += 1
        screenshot.note = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(settle))
            performScreenshotCapture()
            screenshot.isCapturing = false
        }
    }

    private func performScreenshotCapture() {
        guard !state.isQuitting else { return }
        guard let view = panelContentView() else {
            showScreenshotNote("截图失败")
            return
        }
        // A panel flush with the screen edge clips its top-right corner, and
        // that clipped region is blank in the bitmap.
        keepPanelInsideScreen(view)
        guard let shot = PanelScreenshot.capture(view: view) else {
            showScreenshotNote("截图失败")
            return
        }
        guard PanelScreenshot.copyToPasteboard(image: shot.image, png: shot.png) else {
            showScreenshotNote("截图失败")
            return
        }
        showScreenshotNote("已复制到剪贴板")
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
            if abs(view.bounds.width - Self.contentWidth) < 2,
               abs(view.bounds.height - Self.contentHeight) < 2 {
                return view
            }
        }
        return nil
    }

    private func screenshotToast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
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

            Text("数据来源")
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
                    Text("截图")
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .allowsHitTesting(!state.isQuitting && !screenshot.isCapturing)
            .help("把当前榜单截图复制到剪贴板")

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
                        Text("退出中")
                    } else {
                        Image(systemName: "power")
                            .imageScale(.small)
                        Text("退出")
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .allowsHitTesting(!state.isQuitting)
            .help(state.isQuitting ? "正在退出 AI Leaderboards" : "退出 AI Leaderboards")
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
            return (0..<20).map { index in
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

        return (0..<20).map { index in
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
        let entries = state.snapshot.boards[kind]?.entries ?? []
        guard state.selectedGrouping == .company else {
            return entries.map {
                DisplayedLeaderboardEntry(entry: $0, scoreHelp: nil, isCompany: false)
            }
        }
        return CompanyLeaderboard.rank(entries).map { standing in
            DisplayedLeaderboardEntry(
                entry: standing.entry,
                scoreHelp: CompanyLeaderboard.scoreHelp(for: standing),
                isCompany: true
            )
        }
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

    /// Update time follows the board name in that column's header. Artificial
    /// Analysis has no source timestamp, so that side keeps the fetch time and
    /// index version. Arena prefers the vote cutoff.
    private func columnTitle(_ title: String, kind: LeaderboardKind, preferSourceUpdatedAt: Bool) -> String {
        guard let board = state.snapshot.boards[kind] else { return title }
        let date = preferSourceUpdatedAt ? (board.sourceUpdatedAt ?? board.fetchedAt) : board.fetchedAt
        let note = board.sourceNote.map { " (\($0))" } ?? ""
        return "\(title) · \(timestamp(date))\(note)"
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        return Color(hex: OrganizationLogoCatalog.displayBrandColorHex(brandHex, isDark: isDark))
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

    private var entry: LeaderboardEntry? { model?.entry }

    private var isDomestic: Bool {
        OrganizationRegion.isChinese(entry?.organization, modelName: entry?.name)
    }

    /// Same ink as the row wash, so the domestic outline follows that
    /// background instead of a separate hue.
    private var domesticInk: Color {
        model?.brandColor(isDark: colorScheme == .dark) ?? .primary
    }

    var body: some View {
        // Domestic origin is a border so it does not take a layout slot or
        // cover the purchase links.
        HStack(spacing: 10) {
            if let entry {
                ModelLogoView(
                    url: model?.logoURL,
                    organization: entry.organization,
                    name: entry.name
                )
                modelName(entry)
                InlinePurchaseLinks(organization: entry.organization, modelName: entry.name)
            } else {
                Text("-")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(cellBackground)
        .overlay {
            if isDomestic {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(domesticInk, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func modelName(_ entry: LeaderboardEntry) -> some View {
        let name = Text(entry.name)
            .lineLimit(1)
            .truncationMode(.middle)
        if let help = nameHelpText {
            if isDomestic {
                name
                    .help(help)
                    .accessibilityLabel(domesticAccessibilityLabel(entry))
            } else {
                name.help(help)
            }
        } else {
            name
        }
    }

    /// Company mode must not keep saying 国产模型. The border is unchanged;
    /// only the words follow the grouping.
    private var nameHelpText: String? {
        var lines: [String] = []
        if isDomestic {
            lines.append(model?.isCompany == true ? "国产公司" : "国产模型")
        }
        if let scoreHelp = model?.scoreHelp {
            lines.append(scoreHelp)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func domesticAccessibilityLabel(_ entry: LeaderboardEntry) -> String {
        let kind = model?.isCompany == true ? "国产公司" : "国产模型"
        return "\(kind) \(entry.name)"
    }

    private var cellBackground: some View {
        Group {
            if let brandColor = model?.brandColor(isDark: colorScheme == .dark) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(brandColor.opacity(0.34))
                    .overlay(alignment: .leading) {
                        // 3px full-ink bar in the 5px leading padding, so it
                        // does not cover the logo.
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(brandColor)
                            .frame(width: 3)
                            .padding(.leading, 2)
                            .padding(.vertical, 3)
                    }
            }
        }
    }
}

private struct ScoreCell: View {
    @Environment(\.colorScheme) private var colorScheme

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
        .padding(.vertical, 3)
        .background(matchBackground)
    }

    private var matchBackground: some View {
        Group {
            if let brandColor = model?.brandColor(isDark: colorScheme == .dark) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(brandColor.opacity(0.34))
            }
        }
    }
}

private struct InlinePurchaseLinks: View {
    let organization: String?
    let modelName: String

    private var links: PurchaseLinks {
        PurchaseLinkCatalog.links(forOrganization: organization, modelName: modelName)
    }

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: 10) {
                PurchaseLinkControl(title: "套餐", links: links.codingPlan)
                PurchaseLinkControl(title: "按量", links: links.payAsYouGo)
            }
            .font(.caption)
        }
    }
}

private struct PurchaseLinkControl: View {
    let title: String
    let links: [PurchaseLink]

    var body: some View {
        if links.count == 1, let link = links.first {
            // SwiftUI Link shows the pointing-hand cursor and opens the URL
            // itself; an onHover-based cursor here would swallow clicks in
            // NSTableView-backed cells.
            Link(title, destination: link.url)
                .font(.caption)
                .help(link.url.absoluteString)
        } else if links.count > 1 {
            PurchaseMenuLink(title: title, links: links)
        }
    }
}

/// Multi-link trigger painted as a real `Link`, so caption size and link color
/// match the single-URL control. SwiftUI `Menu` + `.borderlessButton` is an
/// `NSPopUpButton` and ignores those styles. The transparent button only
/// handles the click; `onHover` would swallow it inside `NSTableView` cells.
private struct PurchaseMenuLink: View {
    let title: String
    let links: [PurchaseLink]

    private var helpText: String {
        links.map(\.url.absoluteString).joined(separator: "\n")
    }

    var body: some View {
        // String Link, not a custom label: only that initializer is guaranteed
        // to use the same caption face and link color as the single-URL control.
        HStack(spacing: 2) {
            Link(title, destination: links[0].url)
                .font(.caption)
                .allowsHitTesting(false)
            // Same link color as the string Link, not the accent tint. A custom
            // accent would otherwise make the chevron a different color.
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .imageScale(.small)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(nsColor: .linkColor))
                .accessibilityHidden(true)
        }
        .lineLimit(1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background {
            PurchaseMenuButton(links: links, title: title, helpText: helpText)
        }
        .fixedSize()
        .help(helpText)
    }
}

private struct CategorySegmentedControl: NSViewRepresentable {
    static let width: CGFloat = 360
    static let height: CGFloat = 24

    @Binding var selection: LeaderboardCategory

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
        for (index, category) in LeaderboardCategory.allCases.enumerated() {
            control.setLabel(category.title, forSegment: index)
            control.setWidth(segmentWidth, forSegment: index)
        }
        control.selectedSegment = selectedIndex
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.toolTip = "切换榜单类别"
        control.setAccessibilityLabel("榜单类别")
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: CategorySegmentedControlView, context: Context) {
        context.coordinator.selection = $selection
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

    @Binding var selection: LeaderboardGrouping

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
        for (index, grouping) in LeaderboardGrouping.allCases.enumerated() {
            control.setLabel(grouping.title, forSegment: index)
            control.setWidth(segmentWidth, forSegment: index)
        }
        control.selectedSegment = selectedIndex
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.toolTip = "按公司查看时，以最强模型分数为准，弱型号不拉低"
        control.setAccessibilityLabel("榜单分组")
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: CategorySegmentedControlView, context: Context) {
        context.coordinator.selection = $selection
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

private struct PurchaseMenuButton: NSViewRepresentable {

    let links: [PurchaseLink]
    let title: String
    let helpText: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LinkMenuButton {
        let button = LinkMenuButton()
        button.isTransparent = true
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.popUpButton)
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: LinkMenuButton, context: Context) {
        configure(button, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkMenuButton, context: Context) -> CGSize? {
        // An empty proposal must not collapse the hit target to 0×0. Nil lets
        // SwiftUI use the label size; a real proposal fills that label.
        guard let width = proposal.width, let height = proposal.height, width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func configure(_ button: LinkMenuButton, context: Context) {
        context.coordinator.links = links
        button.coordinator = context.coordinator
        button.toolTip = helpText
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(helpText)
    }

    final class Coordinator: NSObject {
        var links: [PurchaseLink] = []

        func popMenu(from button: NSButton) {
            guard !links.isEmpty else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for link in links {
                let item = NSMenuItem(
                    title: link.label,
                    action: #selector(openURL(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = link.url as NSURL
                item.isEnabled = true
                menu.addItem(item)
            }
            // y-up: pin the menu's top-left to the control's bottom-left so it
            // opens downward, the same direction as the old popup.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
        }

        @objc func openURL(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

private final class LinkMenuButton: NSButton {
    weak var coordinator: PurchaseMenuButton.Coordinator?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.popMenu(from: self)
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
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
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

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
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
