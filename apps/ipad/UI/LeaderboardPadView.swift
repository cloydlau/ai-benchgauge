import SwiftUI
import LeaderboardKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
private final class PadPresentationState: ObservableObject {
    @Published var licenseSection: PadLicenseSection?
    @Published var note: String?
}
private enum PadLicenseSection: String, Identifiable {
    case application, notices
    var id: String { rawValue }
}
@MainActor
private final class PadBoardDetail: ObservableObject {
    @Published var selectedCompany: CompanyStanding?
    @Published var showingSource = false
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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    controls
                    boardPair(wide: geometry.size.width >= 760)
                    footer
                }
                .padding(18)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.refresh(force: true) }
        }
        .background(Color.padBackground)
        .overlay(alignment: .bottom) {
            if let note = presentation.note {
                Text(note).font(.footnote).padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(20)
            }
        }
        .sheet(item: $presentation.licenseSection) { licenseSheet($0) }
        .task(id: store.category) { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .environment(\.locale, store.language.locale)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AI BenchGauge").font(.custom("SnellRoundhand-Bold", size: 21)).lineLimit(1)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Button { Task { await store.refresh(force: true) } } label: {
                    HStack(spacing: 8) {
                        Text(tr("UPDATED", "更新时间")).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(LeaderboardPresentation.rankingUpdated(store.snapshot, category: store.category,
                            language: store.language, now: context.date))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(rankingFailed ? Color.orange : Color.secondary)
                            .background((rankingFailed ? Color.orange : Color.secondary).opacity(rankingFailed ? 0.12 : 0.10), in: Capsule())
                    }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.category.boardKinds.contains { store.refreshing.contains($0) })
                .accessibilityLabel(tr("Click to refresh boards", "点击刷新榜单"))
                .accessibilityIdentifier("refresh")
            }
        }
    }
    private var rankingFailed: Bool { store.category.boardKinds.contains { store.failures[$0] != nil && !store.refreshing.contains($0) } }

    // Fixed intrinsic widths avoid a UIKit segmented picker accepting a width
    // it cannot lay out when ViewThatFits probes the horizontal candidate.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { groupingPicker.frame(width: 180); categoryPicker.frame(width: 360) }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { groupingPicker.frame(width: 180); categoryPicker }
        }
    }
    private var categoryPicker: some View {
        Picker(tr("Leaderboard category", "榜单类别"), selection: $store.category) {
            ForEach(LeaderboardCategory.allCases) { category in
                Text(LeaderboardPresentation.title(category, language: store.language)).tag(category)
            }
        }.pickerStyle(.segmented).accessibilityIdentifier("category")
    }
    private var groupingPicker: some View {
        Picker(tr("Grouping", "分组"), selection: $store.grouping) {
            Text(tr("Models", "模型")).tag(LeaderboardGrouping.model)
            Text(tr("Companies", "公司")).tag(LeaderboardGrouping.company)
        }.pickerStyle(.segmented).accessibilityIdentifier("grouping")
    }

    @ViewBuilder private func boardPair(wide: Bool, isImage: Bool = false) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage) }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage) }
            }
        }
    }
    private func boardCard(_ kind: LeaderboardKind, isImage: Bool = false) -> some View {
        PadBoardCard(kind: kind, board: store.snapshot.boards[kind], grouping: store.grouping,
            language: store.language, filter: store.countryFilter(for: kind), failure: store.failures[kind],
            isRefreshing: store.refreshing.contains(kind), isImage: isImage,
            selectCountry: { store.setCountryFilter($0, for: kind) }, copyName: copyName)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(compact: false, showsSources: true)
            footerRow(compact: false, showsSources: false)
            footerRow(compact: true, showsSources: false)
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    private func footerRow(compact: Bool, showsSources: Bool) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                Link(destination: Self.repositoryURL) {
                    if let image = PadOrganizationLogo.image(for: "github") {
                        image.renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13)
                    } else { Image(systemName: "link") }
                }.accessibilityLabel("GitHub")
                Text("Cloyd Lau")
                Text("·")
                Button(compact ? "MIT" : "MIT License") { presentation.licenseSection = .application }.accessibilityIdentifier("license")
                Text("·")
                Button(tr(compact ? "Notices" : "Open-source notices", "开源声明")) { presentation.licenseSection = .notices }
                    .accessibilityIdentifier("open-source-notices")
            }.fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                if showsSources {
                    Text(tr("Sources", "数据来源"))
                    Link(store.category.boardKinds[0].sourceLinkTitle, destination: store.category.boardKinds[0].sourceURL)
                    Text("·")
                    Link(store.category.boardKinds[1].sourceLinkTitle, destination: store.category.boardKinds[1].sourceURL)
                } else {
                    Menu(tr("Sources", "数据来源")) {
                        ForEach(store.category.boardKinds, id: \.self) { kind in Link(kind.sourceLinkTitle, destination: kind.sourceURL) }
                    }
                }
                Text("·")
                Button { copyScreenshot() } label: {
                    if compact { Image(systemName: "camera") }
                    else { Label(tr("Screenshot", "截图"), systemImage: "camera") }
                }.accessibilityLabel(tr("Screenshot", "截图")).accessibilityIdentifier("share")
                Text("·")
                Picker(tr("Language", "语言"), selection: $store.language) {
                    Text("EN").tag(AppLanguage.english)
                    Text("简中").tag(AppLanguage.chinese)
                    Text("繁中").tag(AppLanguage.traditionalChinese)
                }.pickerStyle(.segmented).frame(width: 150).accessibilityIdentifier("language")
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain)
    }

    private func licenseSheet(_ section: PadLicenseSection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if section == .application { Text(Self.license).font(.footnote).textSelection(.enabled) }
                    else { Text(tr("No third-party software is bundled in this edition.", "此版本未打包第三方软件。")) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section == .application ? "MIT License" : tr("Open-source notices", "开源声明"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.licenseSection = nil } } }
        }
    }
    private static var license: String {
        guard let url = Bundle.module.url(forResource: "AI-BenchGauge", withExtension: "txt") else { return "MIT License" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "MIT License"
    }

    func renderLeaderboardImage(width: CGFloat = 1000, scheme: ColorScheme = .light) -> CGImage? {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI BenchGauge").font(.custom("SnellRoundhand-Bold", size: 21))
                Text(tr(store.grouping == .model ? "Models" : "Companies", store.grouping == .model ? "模型" : "公司"))
                Text(LeaderboardPresentation.title(store.category, language: store.language))
                Spacer()
                Text(tr("UPDATED", "更新时间") + " " + LeaderboardPresentation.rankingUpdated(store.snapshot,
                    category: store.category, language: store.language)).font(.caption).foregroundStyle(.secondary)
            }
            boardPair(wide: width >= 760, isImage: true)
            HStack {
                Text("github.com/cloydlau/ai-benchgauge").font(.system(size: 12, design: .monospaced))
                Spacer()
                Text("Cloyd Lau · MIT License")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: width).background(Color.padBackground)
        .environment(\.colorScheme, scheme).environment(\.locale, store.language.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.cgImage
    }
    private func copyScreenshot() {
        guard let cgImage = renderLeaderboardImage(scheme: colorScheme) else {
            showNote(tr("Screenshot failed", "截图失败"))
            return
        }
        #if os(iOS)
        UIPasteboard.general.image = UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cgImage, size: .zero)])
        #endif
        showNote(tr("Copied to clipboard", "已复制到剪贴板"))
    }
    private func copyName(_ name: String) {
        #if os(iOS)
        UIPasteboard.general.string = name
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        #endif
        showNote(tr("Copied ", "已复制 ") + name)
    }
    private func showNote(_ note: String) {
        presentation.note = note
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if presentation.note == note { presentation.note = nil }
        }
    }
}

@MainActor
private struct PadBoardCard: View {
    let kind: LeaderboardKind
    let board: Leaderboard?
    let grouping: LeaderboardGrouping
    let language: AppLanguage
    let filter: LeaderboardCountryFilter
    let failure: LeaderboardFailure?
    let isRefreshing: Bool
    let isImage: Bool
    let selectCountry: (LeaderboardCountryFilter) -> Void
    let copyName: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var detail = PadBoardDetail()
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    private var rows: [LeaderboardEntry] { LeaderboardPresentation.rows(board, grouping: grouping, filter: filter) }
    private var title: String {
        let name = LeaderboardPresentation.title(kind, language: language)
        guard let date = board?.sourceUpdatedAt else { return name }
        let formatter = DateFormatter(); formatter.locale = language.locale; formatter.dateFormat = "M/d HH:mm"
        return name + " · " + formatter.string(from: date)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if isImage { Text(title).font(.subheadline.weight(.medium)) }
                    else { Link(title, destination: kind.sourceURL).font(.subheadline.weight(.medium)) }
                    if isImage { Text(LeaderboardPresentation.explanation(kind, language: language)).foregroundStyle(.secondary) }
                    else {
                        Button { detail.showingSource = true } label: {
                            Text(failure == nil ? LeaderboardPresentation.explanation(kind, language: language) : tr("Refresh failed", "刷新失败"))
                        }.buttonStyle(.plain).foregroundStyle(failure == nil ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("\(failure == nil ? "source-help" : "source-error")-\(kind.rawValue)")
                    }
                }.font(.caption)
                Spacer(minLength: 2)
                if isRefreshing && !isImage { ProgressView().accessibilityLabel(tr("Updating rankings", "正在更新排名")) }
            }.padding(12)
            HStack(spacing: 8) {
                Text(tr("Rank", "排名")).frame(width: 32)
                Spacer()
                Text(tr("Score", "分数")).frame(width: 50)
                if isImage { Text(filter == .all ? tr("Country", "国家") : filter.title(language: language)).frame(minWidth: 44) }
                else {
                    Menu {
                        ForEach(LeaderboardPresentation.countryFilters(board), id: \.self) { option in
                            Button { selectCountry(option) } label: {
                                if option == filter { Label(option.title(language: language), systemImage: "checkmark") }
                                else { Text(option.title(language: language)) }
                            }
                        }
                    } label: { Text(tr("Country", "国家")); Image(systemName: "chevron.down").font(.caption2) }
                    .font(.caption).frame(minWidth: 44).accessibilityIdentifier("country-\(kind.rawValue)")
                    .accessibilityValue(filter.title(language: language))
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 8)
            Divider()
            if board != nil {
                if rows.isEmpty { Text("-").foregroundStyle(.secondary).padding(16) }
                ForEach(Array(rows.prefix(20).enumerated()), id: \.offset) { index, entry in entryRow(entry, rank: index + 1) }
            } else {
                ForEach(1...20, id: \.self) { rank in
                    HStack { Text(LeaderboardPresentation.rankLabel(rank)).frame(width: 32); Spacer(); Text("-").frame(width: 50); Text("-").frame(width: 44) }
                        .font(.subheadline).foregroundStyle(.secondary).padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.padCard, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain).accessibilityIdentifier("board-\(kind.rawValue)")
        .sheet(isPresented: $detail.showingSource) {
            NavigationStack {
                ScrollView { Text(sourceDetails).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                    .navigationTitle(LeaderboardPresentation.title(kind, language: language))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.showingSource = false } } }
            }
        }
        .sheet(isPresented: Binding(get: { detail.selectedCompany != nil }, set: { if !$0 { detail.selectedCompany = nil } })) {
            NavigationStack {
                ScrollView {
                    if let standing = detail.selectedCompany { Text(CompanyLeaderboard.scoreHelp(for: standing, language: language)).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                }.navigationTitle(detail.selectedCompany?.entry.name ?? "")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.selectedCompany = nil } } }
            }
        }
    }

    private var sourceDetails: String {
        let explanation = LeaderboardPresentation.sourceHelp(kind, language: language, board: board)
        guard let failure else { return explanation }
        return failure.message(language: language, hasCachedBoard: board != nil) + "\n\n" + explanation
    }

    private func entryRow(_ entry: LeaderboardEntry, rank: Int) -> some View {
        let country = OrganizationRegion.country(entry.organization, modelName: entry.name)
        return HStack(alignment: .center, spacing: 8) {
            Text(LeaderboardPresentation.rankLabel(rank)).monospacedDigit().frame(width: 32)
            HStack(spacing: 6) {
                PadOrganizationLogo(entry: entry)
                if isImage { Text(entry.name).fixedSize(horizontal: false, vertical: true) }
                else {
                    Button { copyName(entry.name) } label: { Text(entry.name).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).accessibilityLabel(entry.name + tr(", click to copy", "，点击复制"))
                        .accessibilityIdentifier("name-\(kind.rawValue)-\(entry.id)")
                }
                if grouping == .company { purchaseLinks(entry) }
            }.padding(.horizontal, 5).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brandColor(entry).opacity(0.34), in: RoundedRectangle(cornerRadius: 5))
            if grouping == .company && !isImage {
                Button { detail.selectedCompany = LeaderboardPresentation.companies(board, filter: filter).first { $0.entry.id == entry.id } } label: {
                    Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 50, height: 44)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("\(entry.name), \(entry.score), \(tr("score details", "分数说明"))")
                .accessibilityIdentifier("score-\(kind.rawValue)-\(entry.id)")
            } else { Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit().foregroundStyle(.secondary).frame(width: 50) }
            Text(country?.flagEmoji ?? "-").frame(width: 44)
                .accessibilityLabel(country?.localizedName(language: language) ?? tr("Country unknown", "国家未知"))
        }
        .font(.subheadline).padding(.horizontal, 8).frame(minHeight: 44)
        .background(rank.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
    }
    private func purchaseLinks(_ entry: LeaderboardEntry) -> some View {
        let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
        return HStack(spacing: 8) {
            if let link = PurchaseLinkCatalog.preferredLink(from: links.codingPlan, language: language) {
                if isImage { Text(tr("Plan", "套餐")) } else { Link(tr("Plan", "套餐"), destination: link.url) }
            }
            if let link = PurchaseLinkCatalog.preferredLink(from: links.payAsYouGo, language: language) {
                if isImage { Text(tr("Pay as you go", "按量")) } else { Link(tr("Pay as you go", "按量"), destination: link.url) }
            }
        }.font(.caption).fixedSize()
    }
    private func brandColor(_ entry: LeaderboardEntry) -> Color {
        guard let raw = OrganizationLogoCatalog.brandColorHex(forOrganization: entry.organization, modelName: entry.name) else { return .clear }
        let display = OrganizationLogoCatalog.displayBrandColorHex(raw, isDark: colorScheme == .dark, modelName: grouping == .model ? entry.name : nil)
        let value = UInt32(display.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

private struct PadOrganizationLogo: View {
    let entry: LeaderboardEntry
    private var image: Image? {
        guard let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: entry.organization, modelName: entry.name),
              let image = Self.image(for: key) else { return nil }
        return image
    }
    static func image(for key: String) -> Image? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "logos") else { return nil }
        #if os(iOS)
        return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #else
        return NSImage(contentsOf: url).map(Image.init(nsImage:))
        #endif
    }
    var body: some View {
        Group {
            if let image { image.resizable().scaledToFit() }
            else { Color.clear }
        }.frame(width: 18, height: 18).background(.white, in: RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
    }
}
private extension Color {
    static var padBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var padCard: Color { padBackground }
}
