import AppKit
import SwiftUI
import LeaderboardCore

/// Codex provider quotas from the local CC Switch database.
///
/// These are account balances, not properties of a ranked model, so they sit
/// above the table instead of becoming another score column.
struct QuotaStrip: View {
    let chips: [AccountQuotaChip]
    let updatedAt: Date?
    let unavailable: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            strip(now: context.date)
        }
    }

    @ViewBuilder
    private func strip(now: Date) -> some View {
        if chips.isEmpty {
            HStack(spacing: 8) {
                sectionLabel
                Text("CC Switch 暂不可读")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
            }
            .help("无法读取 ~/.cc-switch/cc-switch.db")
        } else {
            HStack(spacing: 8) {
                sectionLabel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            QuotaChipView(chip: chip, now: now)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .frame(height: 28)
                statusLabel(now: now)
            }
        }
    }

    private var sectionLabel: some View {
        Text("Codex 余量")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("本机 CC Switch 里的 Codex 供应商余量，不是榜单分数")
    }

    @ViewBuilder
    private func statusLabel(now: Date) -> some View {
        let text = statusText(now: now)
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(unavailable ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .monospacedDigit()
                .fixedSize()
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

    var body: some View {
        if let url = chip.websiteURL {
            Button {
                NSWorkspace.shared.open(url)
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
        .help(AccountQuotaFormatting.help(for: chip, now: now))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(chip.websiteURL == nil ? [] : .isButton)
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
