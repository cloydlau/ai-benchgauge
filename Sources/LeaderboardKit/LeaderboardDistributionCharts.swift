#if canImport(SwiftUI)
import SwiftUI

/// Shared Apple charts; desktop places these in the ranking's scrollable tail.
public struct LeaderboardDistributionCharts: View {
    @Environment(\.colorScheme) private var colorScheme
    private let distribution: LeaderboardDistribution
    private let language: AppLanguage
    private let boardTitle: String?
    public init(entries: [LeaderboardEntry], language: AppLanguage, boardTitle: String? = nil) {
        distribution = LeaderboardDistribution(entries: entries)
        self.language = language; self.boardTitle = boardTitle
    }
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    private func sourceColor(_ id: String) -> Color {
        guard let openness = ModelOpenness(rawValue: id) else { return Color.secondary.opacity(0.5) }
        return ModelOpennessBadge.tint(for: openness, dark: colorScheme == .dark)
    }
    private func distributionValue(count: Int, percent: String) -> some View {
        HStack(spacing: 3) {
            Text("\(count)").frame(maxWidth: .infinity, alignment: .trailing)
            Text("·")
            Text(percent).frame(width: 42, alignment: .trailing)
        }
        .monospacedDigit().lineLimit(1).frame(width: 82)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count), \(percent)")
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let boardTitle { Text(boardTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
            HStack {
                Text(tr("Country share", "国家占比")).fontWeight(.semibold)
                    .accessibilityIdentifier("country-distribution-heading")
                Spacer(minLength: 4)
                Text(tr("\(distribution.total) models", "\(distribution.total) 个模型")).foregroundStyle(.secondary)
            }
            if distribution.total == 0 {
                Text(tr("No model data yet", "暂无模型数据")).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(distribution.countries) { slice in
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Text(OrganizationCountry(regionCode: slice.id)?.flagEmoji ?? (slice.id == "other" ? "🌐" : "?"))
                                    .font(.system(size: 13)).frame(width: 18).accessibilityHidden(true)
                                Text(slice.countryName(language: language))
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(minWidth: 96, idealWidth: language == .english ? 144 : 96,
                                    maxWidth: language == .english ? 144 : 96, alignment: .leading)
                                .layoutPriority(1)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.07))
                                    Capsule().fill(Color.accentColor.opacity(0.75)).frame(width: geometry.size.width * slice.fraction)
                                }
                            }.frame(minWidth: 24).frame(height: 6).accessibilityHidden(true)
                            distributionValue(count: slice.count, percent: slice.percent)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(slice.countryName(language: language)), \(slice.count), \(slice.percent)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Source share", "源码占比")).fontWeight(.semibold)
                    .accessibilityIdentifier("source-distribution-heading")
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(distribution.sources) { slice in
                            sourceColor(slice.id).frame(width: geometry.size.width * slice.fraction)
                        }
                    }
                    .background(Color.primary.opacity(0.07)).clipShape(Capsule())
                }.frame(height: 10).accessibilityHidden(true)
                ForEach(distribution.sources) { slice in
                    HStack(spacing: 6) {
                        Group {
                            if let openness = ModelOpenness(rawValue: slice.id) {
                                ModelOpennessBadge(openness, language: language, showsTitle: false, iconSize: 11)
                            } else {
                                Text("?").foregroundStyle(.secondary)
                            }
                        }.frame(width: 18, height: 16).accessibilityHidden(true)
                        Text(slice.sourceName(language: language))
                        Spacer(minLength: 4)
                        distributionValue(count: slice.count, percent: slice.percent)
                    }.accessibilityElement(children: .combine)
                }
            }
            Text(tr("All models on this board · counts, not scores", "按全榜模型数量统计，不按分数加权"))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leaderboard-distributions")
    }
}
#endif
