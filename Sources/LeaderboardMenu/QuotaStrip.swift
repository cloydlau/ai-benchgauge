import AppKit
import SwiftUI
import LeaderboardCore

/// Provider quotas from the local CC Switch database.
///
/// These are account balances, not properties of a ranked model, so they sit
/// above the table instead of becoming another score column. A missing CC
/// Switch install, or an official provider with no stored login, stays hidden.
/// Codex does not need to be installed.
struct QuotaStrip: View {
    let chips: [AccountQuotaChip]
    let updatedAt: Date?
    let unavailable: Bool
    let onConnectQwen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            strip(now: context.date)
        }
    }

    @ViewBuilder
    private func strip(now: Date) -> some View {
        if chips.isEmpty {
            if unavailable {
                HStack(spacing: 8) {
                    sectionLabel
                    Text("CC Switch 暂不可读")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("这次没读成本机 CC Switch 数据库")
                    Spacer(minLength: 0)
                }
            }
        } else {
            // Chips keep their full text. A horizontal scroller clipped the reset
            // times and still drew a bar when macOS shows scroll bars always.
            HStack(alignment: .top, spacing: 8) {
                sectionLabel
                    .padding(.top, 5)
                QuotaFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(chips) { chip in
                        QuotaChipView(
                            chip: chip,
                            now: now,
                            onConnectQwen: needsQwenConnection(chip) ? onConnectQwen : nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                statusLabel(now: now)
                    .padding(.top, 5)
            }
        }
    }

    private func needsQwenConnection(_ chip: AccountQuotaChip) -> Bool {
        guard chip.kind == .qwen else { return false }
        if case .usage = chip.status { return true }
        return false
    }

    private var sectionLabel: some View {
        Text("余量")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("来自本机 CC Switch 的供应商余量。没安装 CC Switch 或读不懂配置时不显示，也不需要安装 Codex。")
    }

    @ViewBuilder
    private func statusLabel(now: Date) -> some View {
        let text = statusText(now: now)
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .fixedSize()
                .help(unavailable ? "数据库这次没有读成，显示的是上次余量" : "")
        }
    }

    private func statusText(now: Date) -> String {
        if unavailable { return "未刷新" }
        guard let updatedAt else { return "" }
        let seconds = now.timeIntervalSince(updatedAt)
        if seconds < 45 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1)) 分钟前" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }
}

private struct QuotaChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let chip: AccountQuotaChip
    let now: Date
    let onConnectQwen: (() -> Void)?

    var body: some View {
        if onConnectQwen != nil || chip.websiteURL != nil {
            Button {
                if let onConnectQwen {
                    onConnectQwen()
                } else if let url = chip.websiteURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                chipBody
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        } else {
            chipBody
        }
    }

    private var chipBody: some View {
        let runs = AccountQuotaFormatting.runs(for: chip, now: now)
        return HStack(spacing: 5) {
            logo
            Text(chip.shortName)
                .font(.system(size: 11, weight: chip.isCurrent ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            QuotaRunsText(runs: runs)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(chipBackground)
        .overlay(chipStroke)
        .fixedSize()
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(onConnectQwen == nil && chip.websiteURL == nil ? [] : .isButton)
    }

    private var helpText: String {
        let help = AccountQuotaFormatting.help(for: chip, now: now)
        guard onConnectQwen != nil else { return help }
        return [help, "点击连接千问官网用量"].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var parts = [chip.shortName]
        if chip.isCurrent {
            parts.append("当前供应商")
        }
        let summary = AccountQuotaFormatting.plainSummary(for: chip, now: now)
        if !summary.isEmpty {
            parts.append(summary)
        }
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var logo: some View {
        if let image = bundledLogo {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(0.5)
                .frame(width: 16, height: 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
                .accessibilityHidden(true)
        }
    }

    private var bundledLogo: NSImage? {
        guard let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organizationName),
              let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appending(path: "logos/\(key).png")
        return NSImage(contentsOf: url)
    }

    /// "In use" is a status, not a brand. xAI and Z.ai marks are near-black, so a
    /// brand wash disappears into the logo and reads as a clipped icon.
    private var currentAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.86, blue: 0.58)
            : Color(red: 0.13, green: 0.58, blue: 0.34)
    }

    private var organizationName: String {
        switch chip.kind {
        case .officialNote: "OpenAI"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .xaiOAuth: "xAI"
        case .zhipu: "Z.ai"
        }
    }

    private var chipBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(chip.isCurrent ? currentAccent.opacity(colorScheme == .dark ? 0.20 : 0.12) : Color.primary.opacity(0.04))
    }

    private var chipStroke: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
                chip.isCurrent ? currentAccent.opacity(colorScheme == .dark ? 0.90 : 0.72) : Color.primary.opacity(0.08),
                lineWidth: chip.isCurrent ? 1 : 0.5
            )
    }
}

private struct QuotaRunsText: View {
    let runs: [QuotaTextRun]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        runs.reduce(Text("")) { partial, run in
            partial + Text(run.text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(color(for: run.tone))
        }
        .lineLimit(1)
    }

    private func color(for tone: QuotaTone) -> Color {
        switch tone {
        case .secondary:
            return .secondary
        case .green:
            return colorScheme == .dark
                ? Color(red: 0.49, green: 0.84, blue: 0.55)
                : Color(red: 0.10, green: 0.52, blue: 0.26)
        case .orange:
            return .orange
        case .red:
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.45, blue: 0.42)
                : Color(red: 0.86, green: 0.16, blue: 0.16)
        }
    }
}

/// Lays chips out left to right and starts a new line when the next chip does
/// not fit. A missing or zero width is treated as one row so the first layout
/// pass does not stack every chip.
private struct QuotaFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let arranged = arrange(maxWidth: wrappingWidth(proposal.width), subviews: subviews)
        let width = proposal.width.flatMap { $0.isFinite && $0 > 1 ? $0 : nil } ?? arranged.width
        return CGSize(width: width, height: arranged.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(maxWidth: wrappingWidth(bounds.width), subviews: subviews)
        for row in arranged.rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func wrappingWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite, width > 1 else { return nil }
        return width
    }

    private struct Item {
        let index: Int
        let size: CGSize
        let x: CGFloat
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [Item]
    }

    private struct Arrangement {
        var rows: [Row]
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(maxWidth: CGFloat?, subviews: Subviews) -> Arrangement {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0
        var usedWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            // `x` already includes the gap after the previous chip.
            if let maxWidth, x > 0, x + size.width > maxWidth {
                rows.append(current)
                current = Row(y: current.y + current.height + lineSpacing, height: 0, items: [])
                x = 0
            }
            current.items.append(Item(index: index, size: size, x: x))
            current.height = max(current.height, size.height)
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
        }
        if !current.items.isEmpty || rows.isEmpty {
            rows.append(current)
        }
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return Arrangement(rows: rows, width: usedWidth, height: height)
    }
}
