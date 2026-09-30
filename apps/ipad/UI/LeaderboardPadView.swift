import SwiftUI
import LeaderboardKit

@MainActor
private final class PadPresentationState: ObservableObject {
    @Published var showingSettings = false
    @Published var showingShare = false
    @Published var shareImage: Image?
    @Published var licenseSection: PadLicenseSection?
}

private enum PadLicenseSection: String, Identifiable {
    case application, notices
    var id: String { rawValue }
}

@MainActor
private final class PadCompanyDetail: ObservableObject {
    @Published var selectedCompany: CompanyStanding?
}

@MainActor
public struct LeaderboardPadView: View {
    @ObservedObject private var store: LeaderboardPadStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var presentation = PadPresentationState()
    public static let repositoryURL = URL(string: "https://github.com/cloydlau/ai-benchgauge")!

    public init(store: LeaderboardPadStore) { self.store = store }
    private func tr(_ en: String, _ zh: String) -> String { store.language.text(en, zh) }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        controls
                        boardPair(wide: geometry.size.width >= 760)
                        footer
                    }
                    .padding(20)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await store.refresh(force: true) }
            }
            .background(Color.padBackground)
            .navigationTitle("AI BenchGauge")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await store.refresh(force: true) } } label: {
                        Label(tr("Refresh", "刷新"), systemImage: "arrow.clockwise")
                    }
                    .disabled(store.category.boardKinds.contains { store.refreshing.contains($0) })
                    .accessibilityIdentifier("refresh")
                    Button { prepareShare() } label: { Label(tr("Share", "分享"), systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("share")
                    Button { presentation.showingSettings = true } label: { Label(tr("Settings", "设置"), systemImage: "gearshape") }
                        .accessibilityIdentifier("settings")
                }
            }
            .sheet(isPresented: $presentation.showingSettings) { settings }
            .sheet(isPresented: $presentation.showingShare) { shareSheet }
            .sheet(item: $presentation.licenseSection) { licenseSheet($0) }
            .task(id: store.category) { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
        }
        .environment(\.locale, store.language.locale)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { categoryPicker; groupingPicker.frame(width: 180) }
            VStack(spacing: 12) { categoryPicker; groupingPicker }
        }
    }

    private var categoryPicker: some View {
        Picker(tr("Category", "分类"), selection: $store.category) {
            ForEach(LeaderboardCategory.allCases) { category in
                Text(LeaderboardPresentation.title(category, language: store.language)).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("category")
    }

    private var groupingPicker: some View {
        Picker(tr("Grouping", "分组"), selection: $store.grouping) {
            Text(tr("Models", "模型")).tag(LeaderboardGrouping.model)
            Text(tr("Companies", "公司")).tag(LeaderboardGrouping.company)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("grouping")
    }

    @ViewBuilder private func boardPair(wide: Bool, isImage: Bool = false) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 20) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage) }
            }
        } else {
            VStack(spacing: 20) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage) }
            }
        }
    }

    private func boardCard(_ kind: LeaderboardKind, isImage: Bool = false) -> some View {
        PadBoardCard(kind: kind, board: store.snapshot.boards[kind], grouping: store.grouping,
            language: store.language, country: store.country(for: kind),
            failure: store.failures[kind], isRefreshing: store.refreshing.contains(kind), isImage: isImage) {
                store.setCountry($0, for: kind)
            }
    }

    private var footer: some View {
        HStack {
            Button("MIT License") { presentation.licenseSection = .application }
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                Button(tr("Notices", "开源声明")) { presentation.licenseSection = .notices }
                Link("GitHub", destination: Self.repositoryURL)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func licenseSheet(_ section: PadLicenseSection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if section == .application {
                        Text(Self.license).font(.footnote).textSelection(.enabled)
                    } else {
                        Text(tr("This iPad edition bundles the project's own MIT-licensed leaderboard modules and uses Apple's system frameworks. No additional third-party software is bundled. Desktop libraries and logo assets are not included.",
                            "iPad 版包含本项目采用 MIT 许可证的排行榜模块，并使用 Apple 系统框架，没有额外打包第三方软件。未包含桌面依赖及第三方品牌图片。"))
                        Link("github.com/cloydlau/ai-benchgauge", destination: Self.repositoryURL)
                        Text(Self.license).font(.footnote).textSelection(.enabled)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section == .application ? "MIT License" : tr("Open-source notices", "开源声明"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.licenseSection = nil } } }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section(tr("Language", "语言")) {
                    Picker(tr("Language", "语言"), selection: $store.language) {
                        Text("English").tag(AppLanguage.english)
                        Text("简体中文").tag(AppLanguage.chinese)
                        Text("繁體中文").tag(AppLanguage.traditionalChinese)
                    }
                    .accessibilityIdentifier("language")
                }
                Section(tr("About", "关于")) {
                    Text(tr("iPad edition shows public leaderboards. Refreshes on return when results are older than 24 hours; pull down to refresh at any time.",
                        "iPad 版展示公开排行榜。回到应用时，超过 24 小时的数据会自动刷新，也可随时下拉刷新。"))
                    Text(tr("Desktop account quotas are not available in this edition.", "此版本暂不提供电脑上的账户余量。"))
                    Link("github.com/cloydlau/ai-benchgauge", destination: Self.repositoryURL)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                }
                Section("MIT License") {
                    Text(Self.license).font(.footnote).textSelection(.enabled)
                }
                Section(tr("Open-source notices", "开源声明")) {
                    Text(tr("This iPad edition includes the project's MIT-licensed leaderboard library and Apple's system frameworks. It does not bundle desktop dependencies such as Sparkle. Organization initials are drawn by the app; third-party logo assets are not bundled.",
                        "iPad 版包含本项目采用 MIT 许可证的排行榜模块及 Apple 系统框架，未打包 Sparkle 等桌面依赖。公司标记由应用绘制，未打包第三方品牌图片。"))
                        .font(.footnote)
                }
            }
            .navigationTitle(tr("Settings", "设置"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.showingSettings = false } } }
        }
    }

    private static var license: String {
        guard let url = Bundle.module.url(forResource: "AI-BenchGauge", withExtension: "txt") else { return "MIT License" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "MIT License"
    }

    func renderLeaderboardImage(width: CGFloat = 1000, scheme: ColorScheme = .light) -> CGImage? {
        let content = VStack(alignment: .leading, spacing: 20) {
            Text("AI BenchGauge · \(LeaderboardPresentation.title(store.category, language: store.language))")
                .font(.title2.bold())
            boardPair(wide: width >= 760, isImage: true)
            HStack {
                Text("MIT License")
                Spacer()
                Text("github.com/cloydlau/ai-benchgauge")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: width).background(Color.padBackground)
        .environment(\.colorScheme, scheme)
        .environment(\.locale, store.language.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.cgImage
    }

    private func prepareShare() {
        if let cgImage = renderLeaderboardImage(scheme: colorScheme) { presentation.shareImage = Image(decorative: cgImage, scale: 2) }
        else { presentation.shareImage = nil }
        presentation.showingShare = true
    }

    private var shareSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let shareImage = presentation.shareImage {
                        shareImage.resizable().scaledToFit()
                        ShareLink(item: shareImage, preview: SharePreview("AI BenchGauge", image: shareImage)) {
                            Label(tr("Share leaderboard image", "分享榜单图片"), systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent)
                    } else {
                        Text(tr("The image could not be created. You can still share the project link.", "图片生成失败，仍可分享项目链接。"))
                    }
                    ShareLink(item: Self.repositoryURL) { Label(tr("Share project link", "分享项目链接"), systemImage: "link") }
                }.padding(20)
            }
            .navigationTitle(tr("Share", "分享"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.showingShare = false } } }
        }
    }
}

@MainActor
private struct PadBoardCard: View {
    let kind: LeaderboardKind
    let board: Leaderboard?
    let grouping: LeaderboardGrouping
    let language: AppLanguage
    let country: OrganizationCountry?
    let failure: LeaderboardFailure?
    let isRefreshing: Bool
    let isImage: Bool
    let selectCountry: (OrganizationCountry?) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var detail = PadCompanyDetail()
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    private var rows: [LeaderboardEntry] { LeaderboardPresentation.rows(board, grouping: grouping, country: country) }
    private var countries: [OrganizationCountry] {
        OrganizationCountry.allCases.filter { $0 == country || LeaderboardPresentation.countries(board, grouping: grouping).contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if isImage {
                        Text(LeaderboardPresentation.title(kind, language: language)).font(.headline)
                    } else {
                        Link(LeaderboardPresentation.title(kind, language: language), destination: kind.sourceURL).font(.headline)
                    }
                    Text(LeaderboardPresentation.explanation(kind, language: language)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isRefreshing {
                    if isImage { Text(tr("Refreshing", "刷新中")).font(.caption) }
                    else { ProgressView().accessibilityLabel(tr("Refreshing", "刷新中")) }
                }
            }
            HStack {
                Text("Top 20").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if isImage {
                    Text(country?.localizedName(language: language) ?? tr("All countries", "全部国家")).font(.subheadline).foregroundStyle(.secondary)
                } else {
                Menu {
                    Button(tr("All countries", "全部国家")) { selectCountry(nil) }
                    ForEach(countries, id: \.self) { item in
                        Button("\(item.flagEmoji) \(item.localizedName(language: language))") { selectCountry(item) }
                    }
                } label: {
                    Label(country?.localizedName(language: language) ?? tr("All countries", "全部国家"), systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("country-\(kind.rawValue)")
                }
            }
            if let failure {
                Label(failure.message(language: language, hasCachedBoard: board != nil), systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("source-error-\(kind.rawValue)")
            }
            if let board {
                if let date = board.sourceUpdatedAt {
                    dateLabel(tr("Source updated", "源站更新"), date: date)
                }
                dateLabel(tr("Fetched", "获取于"), date: board.fetchedAt)
                if let note = board.sourceNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                if grouping == .company {
                    Text(isImage ? tr("Score uses each company's strongest model", CompanyLeaderboard.scoreExplanation)
                        : tr("Score uses each company's strongest model. Tap a score for details.", "以最强模型分数为准，轻点分数查看构成。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if rows.isEmpty { Text(tr("No entries for this country in the Top 20.", "Top 20 中没有这个国家的条目。")) .foregroundStyle(.secondary).padding(.vertical, 20) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, entry in entryRow(entry) }
            } else if isRefreshing {
                Text(tr("Loading leaderboard…", "正在加载榜单…")).foregroundStyle(.secondary).padding(.vertical, 24)
            } else if failure == nil {
                Text(tr("Pull down to load this leaderboard.", "下拉刷新以加载榜单。")) .foregroundStyle(.secondary).padding(.vertical, 24)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.padCard, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-\(kind.rawValue)")
        .sheet(isPresented: Binding(get: { detail.selectedCompany != nil }, set: { if !$0 { detail.selectedCompany = nil } })) {
            NavigationStack {
                ScrollView {
                    if let standing = detail.selectedCompany {
                        Text(CompanyLeaderboard.scoreHelp(for: standing, language: language)).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                }
                .navigationTitle(detail.selectedCompany?.entry.name ?? "")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.selectedCompany = nil } } }
            }
        }
    }

    private func dateLabel(_ label: String, date: Date) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(date, format: .dateTime.year().month().day().hour().minute().locale(language.locale))
        }.font(.caption).foregroundStyle(.secondary)
    }

    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
        return HStack(alignment: .center, spacing: 10) {
            Text("\(entry.rank)").monospacedDigit().font(.subheadline).foregroundStyle(.secondary).frame(width: 26)
            PadOrganizationMark(entry: entry)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if grouping == .company {
                    HStack(spacing: 12) {
                        if let link = PurchaseLinkCatalog.preferredLink(from: links.codingPlan, language: language) {
                            if isImage { Text(tr("Plans", "套餐")) } else { Link(tr("Plans", "套餐"), destination: link.url) }
                        }
                        if let link = PurchaseLinkCatalog.preferredLink(from: links.payAsYouGo, language: language) {
                            if isImage { Text(tr("API", "按量")) } else { Link(tr("API", "按量"), destination: link.url) }
                        }
                    }.font(.caption)
                }
            }
            Spacer(minLength: 2)
            if grouping == .company && !isImage {
                Button {
                    detail.selectedCompany = CompanyLeaderboard.rank(board?.entries ?? []).first { $0.entry.id == entry.id }
                } label: { Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit() }
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.name), \(entry.score), \(tr("score details", "分数说明"))")
            } else {
                Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit().font(.subheadline)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(PadOrganizationMark.color(entry, isDark: colorScheme == .dark).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PadOrganizationMark: View {
    let entry: LeaderboardEntry
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text(String((entry.organization ?? entry.name).prefix(1)))
            .font(.caption.bold()).foregroundStyle(Self.color(entry, isDark: colorScheme == .dark))
            .frame(width: 24, height: 24)
            .background(Self.color(entry, isDark: colorScheme == .dark).opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
    static func color(_ entry: LeaderboardEntry, isDark: Bool = false) -> Color {
        let raw = OrganizationLogoCatalog.brandColorHex(forOrganization: entry.organization, modelName: entry.name) ?? "#777777"
        let display = OrganizationLogoCatalog.displayBrandColorHex(raw, isDark: isDark)
        let value = UInt32(display.dropFirst(), radix: 16) ?? 0x777777
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

}

private extension Color {
    static var padBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var padCard: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
