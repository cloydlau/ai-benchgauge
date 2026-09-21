import SwiftUI
import LeaderboardCore

struct LeaderboardView: View {
    @ObservedObject var state: AppState

    static let contentWidth: CGFloat = 1040
    static let contentHeight: CGFloat = 830

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Divider()
            footer
        }
        .frame(width: Self.contentWidth, height: Self.contentHeight)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("AI Leaderboards")
                        .font(.system(size: 17, weight: .semibold))
                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                HStack(spacing: 10) {
                    updateStatus
                    if let artificialAnalysis = state.snapshot.boards[selectedCategory.leftKind] {
                        let note = artificialAnalysis.sourceNote.map { " (\($0))" } ?? ""
                        Text("\(selectedCategory.leftKind.sourcePrefix) \(timestamp(artificialAnalysis.fetchedAt))\(note)")
                    }
                    if let arena = state.snapshot.boards[selectedCategory.rightKind] {
                        Text("\(selectedCategory.rightKind.sourcePrefix) \(timestamp(arena.sourceUpdatedAt ?? arena.fetchedAt))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            categoryPicker
            Spacer()
            Text(nextRunLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var categoryPicker: some View {
        Picker(
            "榜单类别",
            selection: Binding(
                get: { state.selectedCategory },
                set: { state.selectCategory($0) }
            )
        ) {
            ForEach(LeaderboardCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 360)
        .help("切换榜单类别")
    }

    private var selectedCategory: LeaderboardCategory {
        state.selectedCategory
    }

    @ViewBuilder
    private var updateStatus: some View {
        if state.isRefreshing {
            Text("更新中")
        } else if state.lastErrors.isEmpty {
            Text("已更新")
        } else {
            Text("部分榜单更新失败，将按计划重试")
                .foregroundStyle(.orange)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // Column widths for the native table; the header row comes from SwiftUI,
    // so nothing has to be hand-aligned any more.
    private var table: some View {
        Table(rows) {
            TableColumn("排名") { row in
                Text(rankLabel(row.rank))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(min: 36, ideal: 48, max: 56)
            .alignment(.center)

            TableColumn(selectedCategory.leftColumnTitle) { row in
                LeaderboardCell(model: row.left)
            }
            .width(min: 300, ideal: 402, max: 460)

            TableColumn("\(selectedCategory.leftKind.sourcePrefix) 分数") { row in
                ScoreCell(model: row.left, scoreDigits: 1)
            }
            .width(min: 56, ideal: 66, max: 76)
            .alignment(.trailing)

            TableColumn(selectedCategory.rightColumnTitle) { row in
                LeaderboardCell(model: row.right)
            }
            .width(min: 300, ideal: 402, max: 460)

            TableColumn("\(selectedCategory.rightKind.sourcePrefix) 分数") { row in
                ScoreCell(model: row.right, scoreDigits: 1)
            }
            .width(min: 56, ideal: 72, max: 82)
            .alignment(.trailing)
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
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "power")
                        .imageScale(.small)
                    Text("退出")
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("退出 AI Leaderboards")
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

    private var nextRunLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let retryAt = state.schedule.retryAfterFailureAt, retryAt < state.schedule.giveUpAt {
            return "下次重试 \(formatter.string(from: retryAt))"
        }
        return "每日更新 \(formatter.string(from: state.schedule.dailyRunAt))"
    }

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

        let left = state.snapshot.boards[selectedCategory.leftKind]?.entries ?? []
        let right = state.snapshot.boards[selectedCategory.rightKind]?.entries ?? []
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

    private func cellModel(
        for entry: LeaderboardEntry?,
        organizationLogos: [String: URL]
    ) -> LeaderboardCellModel? {
        guard let entry else { return nil }
        return LeaderboardCellModel(
            entry: entry,
            brandColor: OrganizationLogoCatalog.brandColorHex(forOrganization: entry.organization)
                .flatMap(Color.init(hex:)),
            logoURL: entry.logoURL ?? entry.organization.flatMap {
                organizationLogos[normalizedOrganization($0)]
            } ?? OrganizationLogoCatalog.logoURL(forOrganization: entry.organization)
        )
    }

    private var organizationLogos: [String: URL] {
        var logos = (state.snapshot.boards[selectedCategory.leftKind]?.organizationLogoURLs ?? [:])
            .reduce(into: [String: URL]()) { result, item in
                result[normalizedOrganization(item.key)] = item.value
            }

        for entry in state.snapshot.boards[selectedCategory.leftKind]?.entries ?? [] {
            guard let organization = entry.organization,
                  let logoURL = entry.logoURL else { continue }
            logos[normalizedOrganization(organization)] = logoURL
        }
        return logos
    }

    private func normalizedOrganization(_ organization: String) -> String {
        let words = organization
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()

        switch words {
        case "moonshot":
            return "kimi"
        case "alibaba":
            return "qwen"
        case "zai":
            return "zai"
        case "thinkingmachines":
            return "thinkingmachines"
        default:
            return words
        }
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
        case .general, .coding: "Artificial Analysis Intelligence Index"
        case .image: "AA | 文生图"
        case .video: "AA | 文生视频"
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

private struct LeaderboardCellModel {
    let entry: LeaderboardEntry
    let brandColor: Color?
    let logoURL: URL?
}

private extension LeaderboardCellModel {
    static func placeholder(rank: Int) -> LeaderboardCellModel {
        LeaderboardCellModel(
            entry: LeaderboardEntry(rank: rank, name: "Placeholder Model", score: 0),
            brandColor: nil,
            logoURL: nil
        )
    }
}

private struct LeaderboardCell: View {
    let model: LeaderboardCellModel?

    private var entry: LeaderboardEntry? { model?.entry }

    var body: some View {
        HStack(spacing: 10) {
            if let entry {
                ModelLogoView(
                    url: model?.logoURL,
                    organization: entry.organization,
                    name: entry.name
                )
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if OrganizationRegion.isChinese(entry.organization) {
                    // Quiet metadata tag: neutral fill + hairline outline reads
                    // as a label, clearly distinct from the blue purchase links.
                    Text("国产")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.primary.opacity(0.04))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
                InlinePurchaseLinks(organization: entry.organization)
            } else {
                Text("-")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(cellBackground)
    }

    private var cellBackground: some View {
        Group {
            if let brandColor = model?.brandColor {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(brandColor.opacity(0.16))
                    Capsule()
                        .fill(brandColor)
                        .frame(width: 3)
                        .padding(.vertical, 1)
                }
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(matchBackground)
    }

    private var matchBackground: some View {
        Group {
            if let brandColor = model?.brandColor {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(brandColor.opacity(0.16))
            }
        }
    }
}

private struct InlinePurchaseLinks: View {
    let organization: String?

    private var links: PurchaseLinks {
        PurchaseLinkCatalog.links(forOrganization: organization)
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
            Menu {
                ForEach(links) { link in
                    Button(link.label) {
                        NSWorkspace.shared.open(link.url)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(title)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(links.map(\.url.absoluteString).joined(separator: "\n"))
        }
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
        guard let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organization),
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

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

private extension Color {
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
