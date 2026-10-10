import AppKit
import CoreImage
import SwiftUI
import LeaderboardCore

/// Provider quotas from the local CC Switch database.
///
/// These are account balances, not properties of a ranked model, so they sit
/// above the table instead of becoming another score column. A missing CC
/// Switch install, or an official provider with no stored login, stays hidden.
/// Reading stored quotas does not require Codex. Direct OpenAI reauthorization
/// uses its official account service through the app's connection controller.
struct QuotaStrip: View {
    let chips: [AccountQuotaChip]
    let language: AppLanguage
    let onConnectQwen: () -> Void
    let onConnectOpenAI: (AccountQuotaChip) -> Void
    let onConnectXAI: (AccountQuotaChip) -> Void
    let onRecoverGLM: (AccountQuotaChip) -> Void
    let onAddModel: () -> Void
    let connectingOpenAIProviderID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Chips keep their full text. Freshness lives in the header caption,
            // so a timestamp cannot sit on this row and steal width from wrapping.
            // Plans by expiry, then metered providers. Keep stored refresh identity stable.
            QuotaFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(AccountQuotaFormatting.sortedChips(chips)) { chip in
                    QuotaChipView(
                        chip: chip,
                        now: context.date,
                        language: language,
                        onConnectQwen: needsQwenConnection(chip) ? onConnectQwen : nil,
                        onConnectOpenAI: { onConnectOpenAI(chip) },
                        onConnectXAI: { onConnectXAI(chip) },
                        onRecoverGLM: { onRecoverGLM(chip) },
                        isConnectingOpenAI: connectingOpenAIProviderID == chip.id
                    )
                }
                AddModelButton(language: language, action: onAddModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func needsQwenConnection(_ chip: AccountQuotaChip) -> Bool {
        guard chip.kind == .qwen else { return false }
        switch chip.status {
        case .note, .message: return true
        case .pending, .windows, .balances, .qwenPlan, .qwenWebsite: return false
        }
    }
}

struct AddModelButton: View {
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(language.text("Add model", "添加模型"), systemImage: "plus")
                .font(.system(size: 11))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .fixedSize()
        .pointingHandCursor()
        .help(language.text("Add a model provider to view its quota", "添加模型供应商，查看其余量"))
        .accessibilityIdentifier("add-model")
    }
}

private struct QuotaChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let chip: AccountQuotaChip
    let now: Date
    let language: AppLanguage
    let onConnectQwen: (() -> Void)?
    let onConnectOpenAI: () -> Void
    let onConnectXAI: () -> Void
    let onRecoverGLM: () -> Void
    let isConnectingOpenAI: Bool

    var body: some View {
        if isClickable {
            Button {
                if AccountQuotaFormatting.glmRecoveryAction(for: chip) != nil {
                    onRecoverGLM()
                } else if requiresOpenAISignIn {
                    onConnectOpenAI()
                } else if requiresXAISignIn || AccountQuotaFormatting.requiresXAISubscriptionConnection(chip) {
                    onConnectXAI()
                } else if let onConnectQwen {
                    onConnectQwen()
                } else if let url = chip.websiteURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                chipBody
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(isConnectingOpenAI || (chip.kind == .zhipu && chip.status == .pending))
        } else {
            chipBody
        }
    }

    private var isClickable: Bool {
        AccountQuotaFormatting.glmRecoveryAction(for: chip) != nil || requiresOpenAISignIn || requiresXAISignIn || AccountQuotaFormatting.requiresXAISubscriptionConnection(chip) || onConnectQwen != nil || chip.websiteURL != nil
    }

    private var requiresOpenAISignIn: Bool {
        chip.kind == .officialNote && (isConnectingOpenAI || chip.status == .message(AccountQuotaMessage.reauthRequired))
    }

    /// Usage OAuth and the subscription-date website session have separate flows.
    private var requiresXAISignIn: Bool {
        AccountQuotaFormatting.requiresXAISignIn(chip)
    }

    /// Usage-window exhaustion retains its red warning. Unpurchased plans
    /// and empty wallets use the neutral dimmed presentation below.
    private var isExhausted: Bool {
        AccountQuotaFormatting.isExhausted(chip)
    }

    private var isDimmed: Bool {
        AccountQuotaFormatting.isDimmed(chip)
    }

    private var chipBody: some View {
        let runs = AccountQuotaFormatting.runs(for: chip, now: now).map {
            QuotaTextRun(text: language.quotaText($0.text), tone: $0.tone)
        }
        return HStack(spacing: 5) {
            logo
                .saturation(isExhausted || isDimmed ? 0 : 1)
                .opacity(isExhausted || isDimmed ? 0.55 : 1)
            Text(language.providerName(chip.kind) + providerSuffix)
                .font(.system(size: 11, weight: chip.isCurrent ? .semibold : .medium))
                .foregroundStyle(isExhausted || isDimmed ? .secondary : .primary)
                .strikethrough(isExhausted && !isDimmed, color: exhaustedAccent)
                .lineLimit(1)
            if isConnectingOpenAI {
                Text(language.text("Waiting for authorization", "等待授权"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                QuotaRunsText(runs: runs, dimmed: isDimmed)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(chipBackground)
        .overlay(chipStroke)
        .fixedSize()
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isClickable ? .isButton : [])
    }

    private var helpText: String {
        if requiresOpenAISignIn {
            return language.text(
                "Click to authorize OpenAI in your browser. Your quota refreshes automatically when sign-in finishes.",
                "点击在浏览器中授权 OpenAI；登录成功后，余量会自动刷新。"
            )
        }
        if requiresXAISignIn {
            return language.text(
                "Click to sign in to Grok in your browser. Your quota refreshes automatically after authorization.",
                "点击在浏览器中登录 Grok；授权成功后，余量会自动刷新。"
            )
        }
        let help = AccountQuotaFormatting.help(for: chip, now: now)
            .components(separatedBy: "\n")
            .map(language.quotaText)
            .joined(separator: "\n")
        let exhaustedNotice = language.text("Quota exhausted; temporarily unavailable", "额度已用尽，暂不可用")
        let balanceHelp = balanceColorHelp
        let detailedHelp = [help, balanceHelp].filter { !$0.isEmpty }.joined(separator: "\n")
        let exhaustedHelp = isExhausted ? [exhaustedNotice, detailedHelp].joined(separator: "\n") : detailedHelp
        guard onConnectQwen != nil else { return exhaustedHelp }
        return [exhaustedHelp, language.text("Click to connect Qwen usage", "点击连接千问官网用量")]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var balanceColorHelp: String {
        guard case let .balances(balances) = chip.status else { return "" }
        var seen = Set<String>()
        return balances.compactMap { balance -> String? in
            guard let reference = QuotaColorScale.balanceReference(currency: balance.currency) else { return nil }
            let amount: (Double) -> String = {
                AccountQuotaFormatting.balanceText(amount: $0, currency: balance.currency)
            }
            let text = language.text(
                "Color reference: \(amount(0)) red, \(amount(reference.orange)) orange, \(amount(reference.yellow)) yellow, \(amount(reference.green))+ green; continuous transitions in between.",
                "金额颜色参考：\(amount(0)) 红、\(amount(reference.orange)) 橙、\(amount(reference.yellow)) 黄、\(amount(reference.green)) 及以上绿；中间连续过渡。"
            )
            return seen.insert(text).inserted ? text : nil
        }.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var parts = [language.providerName(chip.kind) + providerSuffix]
        if chip.isCurrent {
            parts.append(language.text("Current provider", "当前供应商"))
        }
        if isExhausted {
            parts.append(language.text("Quota exhausted; unavailable", "额度已用尽，不可用"))
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
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard isDimmed || isExhausted,
              let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        // Rasterize the monochrome mark so native captures and the live view
        // both render it without depending on a compositing-only color effect.
        let filtered = CIImage(cgImage: original).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let gray = Self.logoImageContext.createCGImage(filtered, from: filtered.extent) else { return image }
        return NSImage(cgImage: gray, size: image.size)
    }

    private static let logoImageContext = CIContext()

    /// "In use" is a status, not a brand. xAI and Z.ai marks are near-black, so a
    /// brand wash disappears into the logo and reads as a clipped icon.
    private var currentAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.86, blue: 0.58)
            : Color(red: 0.13, green: 0.58, blue: 0.34)
    }

    private var quotaAccent: Color? {
        AccountQuotaFormatting.cardColorLevel(for: chip, now: now).map {
            remainingQuotaColor($0, dark: colorScheme == .dark)
        }
    }

    private var exhaustedAccent: Color {
        remainingQuotaColor(0, dark: colorScheme == .dark)
    }

    private var organizationName: String {
        switch chip.kind {
        case .officialNote: "OpenAI"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .xaiOAuth: "xAI"
        case .zhipu: "Z.ai"
        case .minimax: "MiniMax"
        case .stepfun: "StepFun"
        case .blackForestLabs: "Black Forest Labs"
        case .luma: "Luma"
        case .claude: "Anthropic"
        case .gemini: "Google"
        }
    }

    private var chipBackground: some View {
        let fill: Color
        if isDimmed {
            fill = Color.primary.opacity(0.04)
        } else if let quotaAccent {
            fill = quotaAccent.opacity(chip.isCurrent
                ? (colorScheme == .dark ? 0.20 : 0.12)
                : (colorScheme == .dark ? 0.12 : 0.06))
        } else if isExhausted {
            fill = exhaustedAccent.opacity(colorScheme == .dark ? 0.22 : 0.12)
        } else {
            fill = chip.isCurrent
                ? currentAccent.opacity(colorScheme == .dark ? 0.20 : 0.12)
                : Color.primary.opacity(0.04)
        }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
    }

    @ViewBuilder
    private var chipStroke: some View {
        if chip.isCurrent {
            let color = if isDimmed {
                Color.secondary.opacity(colorScheme == .dark ? 0.45 : 0.30)
            } else if let quotaAccent {
                quotaAccent.opacity(colorScheme == .dark ? 0.90 : 0.72)
            } else if isExhausted {
                exhaustedAccent.opacity(colorScheme == .dark ? 0.95 : 0.80)
            } else {
                currentAccent.opacity(colorScheme == .dark ? 0.90 : 0.72)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        }
    }
}

private struct QuotaRunsText: View {
    let runs: [QuotaTextRun]
    var dimmed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        runs.reduce(Text("")) { partial, run in
            partial + Text(run.text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : color(for: run.tone))
        }
        .lineLimit(1)
    }

    private func color(for tone: QuotaTone) -> Color {
        switch tone {
        case .secondary:
            return .secondary
        case .green:
            return remainingQuotaColor(100, dark: colorScheme == .dark)
        case .orange:
            return .orange
        case .red:
            return remainingQuotaColor(0, dark: colorScheme == .dark)
        case let .remaining(percent):
            return remainingQuotaColor(percent, dark: colorScheme == .dark)
        case let .deadline(level):
            return remainingQuotaColor(level, dark: colorScheme == .dark)
        case let .balance(amount, currency):
            guard let level = QuotaColorScale.balanceLevel(amount: amount, currency: currency) else { return .secondary }
            return remainingQuotaColor(level, dark: colorScheme == .dark)
        }
    }
}

private func remainingQuotaColor(_ percent: Double, dark: Bool) -> Color {
    let rgb = QuotaColorScale.color(remainingPercent: percent, dark: dark)
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
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
