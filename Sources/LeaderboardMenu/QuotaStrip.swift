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
    let language: AppLanguage
    let onConnectQwen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Chips keep their full text. Freshness lives in the header caption,
            // so a timestamp cannot sit on this row and steal width from wrapping.
            // Soonest expiry first. Stored chip order stays stable for refresh identity.
            QuotaFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(AccountQuotaFormatting.sortedChips(chips)) { chip in
                    QuotaChipView(
                        chip: chip,
                        now: context.date,
                        language: language,
                        onConnectQwen: needsQwenConnection(chip) ? onConnectQwen : nil
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func needsQwenConnection(_ chip: AccountQuotaChip) -> Bool {
        guard chip.kind == .qwen else { return false }
        if case let .note(text, _) = chip.status, text == AccountQuotaMessage.connectOfficial {
            return true
        }
        return false
    }
}

private struct QuotaChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let chip: AccountQuotaChip
    let now: Date
    let language: AppLanguage
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

    /// Any window at zero remaining makes the whole provider unusable, so
    /// the chip wears the failure, not just the 0% run: red wash and stroke,
    /// struck-through name, and a dimmed monochrome logo.
    private var isExhausted: Bool {
        AccountQuotaFormatting.isExhausted(chip)
    }

    private var chipBody: some View {
        let runs = AccountQuotaFormatting.runs(for: chip, now: now).map {
            QuotaTextRun(text: language.quotaText($0.text), tone: $0.tone)
        }
        return HStack(spacing: 5) {
            logo
<<<<<<< Updated upstream
            Text(language.providerName(chip.kind) + providerSuffix)
=======
                .saturation(isExhausted ? 0 : 1)
                .opacity(isExhausted ? 0.55 : 1)
            Text(chip.shortName)
>>>>>>> Stashed changes
                .font(.system(size: 11, weight: chip.isCurrent ? .semibold : .medium))
                .foregroundStyle(isExhausted ? .secondary : .primary)
                .strikethrough(isExhausted, color: exhaustedAccent)
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
<<<<<<< Updated upstream
            .components(separatedBy: "\n")
            .map(language.quotaText)
            .joined(separator: "\n")
        guard onConnectQwen != nil else { return help }
        return [help, language.text("Click to connect Qwen usage", "点击连接千问官网用量")]
            .filter { !$0.isEmpty }.joined(separator: "\n")
=======
        let exhaustedHelp = isExhausted ? ["额度已用尽，暂不可用", help].joined(separator: "\n") : help
        guard onConnectQwen != nil else { return exhaustedHelp }
        return [exhaustedHelp, "点击连接千问官网用量"].filter { !$0.isEmpty }.joined(separator: "\n")
>>>>>>> Stashed changes
    }

    private var accessibilityLabel: String {
        var parts = [language.providerName(chip.kind) + providerSuffix]
        if chip.isCurrent {
            parts.append(language.text("Current provider", "当前供应商"))
        }
        if isExhausted {
            parts.append("额度已用尽，不可用")
        }
        let summary = AccountQuotaFormatting.plainSummary(for: chip, now: now)
        if !summary.isEmpty {
            parts.append(language.quotaText(summary))
        }
        return parts.joined(separator: language.text(", ", "，"))
    }

    private var providerSuffix: String {
        let base = language.providerName(chip.kind)
        return chip.shortName.hasPrefix(base) ? String(chip.shortName.dropFirst(base.count)) : ""
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

    /// Matches the red run tone so the chip frame and the 0% text agree.
    private var exhaustedAccent: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.45, blue: 0.42)
            : Color(red: 0.86, green: 0.16, blue: 0.16)
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
        let fill: Color
        if isExhausted {
            fill = exhaustedAccent.opacity(colorScheme == .dark ? 0.22 : 0.12)
        } else {
            fill = chip.isCurrent
                ? currentAccent.opacity(colorScheme == .dark ? 0.20 : 0.12)
                : Color.primary.opacity(0.04)
        }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
    }

    private var chipStroke: some View {
        let isEmphasized = isExhausted || chip.isCurrent
        let color: Color
        if isExhausted {
            color = exhaustedAccent.opacity(colorScheme == .dark ? 0.95 : 0.80)
        } else {
            color = chip.isCurrent
                ? currentAccent.opacity(colorScheme == .dark ? 0.90 : 0.72)
                : Color.primary.opacity(0.08)
        }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(color, lineWidth: isEmphasized ? 1 : 0.5)
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

/// Marks the quota chip row so a screenshot can replace that band. Hits pass
/// through; the chips drawn above this background keep their clicks.
struct QuotaStripAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = QuotaStripAnchorView()
        view.identifier = PanelScreenshot.quotaStripIdentifier
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.identifier = PanelScreenshot.quotaStripIdentifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height, width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

private final class QuotaStripAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
