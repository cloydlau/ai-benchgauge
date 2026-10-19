import Foundation

/// Counts models, never scores or company aggregates. Unknown metadata remains a part of the total.
public struct LeaderboardDistribution: Codable, Sendable {
    public struct Slice: Identifiable, Equatable, Codable, Sendable {
        public let id: String
        public let count: Int
        public let total: Int
        public var fraction: Double { total == 0 ? 0 : Double(count) / Double(total) }
        public var percent: String {
            guard total > 0 else { return "—" }
            if count > 0 && fraction < 0.001 { return "<0.1%" }
            return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), fraction * 100)
        }
        public func countryName(language: AppLanguage) -> String {
            if id == "unknown" { return language.text("Unknown", "未知") }
            if id == "other" { return language.text("Other", "其他") }
            return OrganizationCountry(regionCode: id)?.localizedName(language: language) ?? id
        }
        public func sourceName(language: AppLanguage) -> String {
            ModelOpenness(rawValue: id)?.title(language: language) ?? language.text("Unknown", "未知")
        }
    }
    public let total: Int
    public let countries: [Slice]
    public let sources: [Slice]

    public init(entries: [LeaderboardEntry]) {
        total = entries.count
        var countryCounts: [String: Int] = [:], sourceCounts: [String: Int] = [:]
        for entry in entries {
            countryCounts[OrganizationRegion.country(for: entry)?.regionCode ?? "unknown", default: 0] += 1
            sourceCounts[entry.resolvedOpenness?.rawValue ?? "unknown", default: 0] += 1
        }
        let known = countryCounts.filter { $0.key != "unknown" }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        var compact = known.prefix(5).map { Slice(id: $0.key, count: $0.value, total: entries.count) }
        let other = known.dropFirst(5).reduce(0) { $0 + $1.value }
        if other > 0 { compact.append(Slice(id: "other", count: other, total: entries.count)) }
        if let unknown = countryCounts["unknown"] { compact.append(Slice(id: "unknown", count: unknown, total: entries.count)) }
        countries = compact
        sources = ["open", "closed", "unknown"].filter { $0 != "unknown" || sourceCounts[$0] != nil }
            .map { Slice(id: $0, count: sourceCounts[$0] ?? 0, total: entries.count) }
    }
}
