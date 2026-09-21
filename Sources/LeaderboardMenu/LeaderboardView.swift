import SwiftUI
import LeaderboardCore

struct LeaderboardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            footer
        }
        .frame(width: 1000, height: 830)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Leaderboards")
                    .font(.system(size: 17, weight: .semibold))
                if state.isRefreshing {
                    Text("更新中")
                        .foregroundStyle(.secondary)
                } else if state.lastErrors.isEmpty {
                    Text("已更新")
                        .foregroundStyle(.secondary)
                } else {
                    Text("部分榜单更新失败，将按计划重试")
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                Text(nextRunLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // Fixed column widths keep the custom (clickable) header row aligned
    // with the table below; the built-in headers are hidden.
    private static let rankWidth: CGFloat = 48
    private static let modelWidth: CGFloat = 402
    private static let aaScoreWidth: CGFloat = 66
    private static let arenaScoreWidth: CGFloat = 72

    private var table: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            Table(rows) {
                TableColumn("排名") { row in
                    Text("\(row.rank)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(Self.rankWidth)
                .alignment(.center)

                TableColumn(artificialAnalysisTitle) { row in
                    LeaderboardCell(model: row.artificialAnalysis)
                }
                .width(Self.modelWidth)

                TableColumn("AA 分数") { row in
                    ScoreCell(model: row.artificialAnalysis, scoreDigits: 1)
                }
                .width(Self.aaScoreWidth)
                .alignment(.trailing)

                TableColumn(arenaTitle) { row in
                    LeaderboardCell(model: row.arena)
                }
                .width(Self.modelWidth)

                TableColumn("Arena 分数") { row in
                    ScoreCell(model: row.arena, scoreDigits: 1)
                }
                .width(Self.arenaScoreWidth)
                .alignment(.trailing)
            }
            .tableColumnHeaders(.hidden)
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("排名")
                .frame(width: Self.rankWidth)
            headerLink(
                title: artificialAnalysisTitle,
                url: "https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index"
            )
            .frame(width: Self.modelWidth, alignment: .leading)
            Text("AA 分数")
                .frame(width: Self.aaScoreWidth, alignment: .trailing)
            headerLink(
                title: arenaTitle,
                url: "https://arena.ai/leaderboard/code/webdev"
            )
            .frame(width: Self.modelWidth, alignment: .leading)
            Text("Arena 分数")
                .frame(width: Self.arenaScoreWidth, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
    }

    private func headerLink(title: String, url: String) -> some View {
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
        .help(url)
    }

    private var footer: some View {
        HStack {
            if let artificialAnalysis = state.snapshot.boards[.artificialAnalysis] {
                Text("AA \(timestamp(artificialAnalysis.fetchedAt))")
            }
            Spacer()
            if let arena = state.snapshot.boards[.codeArenaWebDev] {
                Text("Arena \(timestamp(arena.sourceUpdatedAt ?? arena.fetchedAt))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var artificialAnalysisTitle: String {
        if let board = state.snapshot.boards[.artificialAnalysis],
           let note = board.sourceNote {
            return "Artificial Analysis (\(note))"
        }
        return "Artificial Analysis Intelligence Index"
    }

    private var arenaTitle: String {
        if let updatedAt = state.snapshot.boards[.codeArenaWebDev]?.sourceUpdatedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/M/d"
            return "Code Arena | WebDev (\(formatter.string(from: updatedAt)))"
        }
        return "Code Arena | WebDev"
    }

    private var nextRunLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let retryAt = state.schedule.retryAfterFailureAt, retryAt < state.schedule.giveUpAt {
            return "下次重试 \(formatter.string(from: retryAt))"
        }
        return "每日更新 \(formatter.string(from: state.schedule.dailyRunAt))"
    }

    private var rows: [LeaderboardRow] {
        let aa = state.snapshot.boards[.artificialAnalysis]?.entries ?? []
        let arena = state.snapshot.boards[.codeArenaWebDev]?.entries ?? []
        let organizationLogos = self.organizationLogos

        return (0..<20).map { index in
            LeaderboardRow(
                rank: index + 1,
                artificialAnalysis: cellModel(
                    for: index < aa.count ? aa[index] : nil,
                    organizationLogos: organizationLogos
                ),
                arena: cellModel(
                    for: index < arena.count ? arena[index] : nil,
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
        var logos = (state.snapshot.boards[.artificialAnalysis]?.organizationLogoURLs ?? [:])
            .reduce(into: [String: URL]()) { result, item in
                result[normalizedOrganization(item.key)] = item.value
            }

        for entry in state.snapshot.boards[.artificialAnalysis]?.entries ?? [] {
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

private struct LeaderboardRow: Identifiable {
    let rank: Int
    let artificialAnalysis: LeaderboardCellModel?
    let arena: LeaderboardCellModel?
    var id: Int { rank }
}

private struct LeaderboardCellModel {
    let entry: LeaderboardEntry
    let brandColor: Color?
    let logoURL: URL?
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
                    Text("国产")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.red.opacity(0.12))
                        )
                }
                InlinePurchaseLinks(organization: entry.organization)
            } else {
                Text("-")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
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
            Button(title) {
                open(link.url)
            }
            .buttonStyle(.link)
            .font(.caption)
            .help(link.url.absoluteString)
        } else if links.count > 1 {
            Menu {
                ForEach(links) { link in
                    Button(link.label) {
                        open(link.url)
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

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
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
