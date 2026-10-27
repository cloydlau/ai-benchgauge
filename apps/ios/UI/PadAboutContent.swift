import Foundation
import LeaderboardKit

struct PadAboutContent: Decodable, Sendable {
    struct Source: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let url: String
        var domain: String { URL(string: url)?.host ?? url }
    }
    struct Schedule: Decodable, Sendable {
        let startedAt: Double
        let meanMonthMilliseconds: Double
        func months(at date: Date) -> Int {
            CalmmitCostCalculation.developmentMonths(startedAt: startedAt,
                now: date.timeIntervalSince1970 * 1000, meanMonthMilliseconds: meanMonthMilliseconds)
        }
    }
    struct Copy: Decodable, Sendable {
        let descriptionLines: [String]
        let platforms: Platforms
        let artwork: Artwork
        let investment: Investment
    }
    struct Artwork: Decodable, Sendable {
        struct Credit: Decodable, Identifiable, Sendable {
            let id: String
            let role: String
            let name: String
            let url: URL
            let detail: String
            let sourceIcon: String
        }
        let image: String
        let sourceURL: URL
        let width: Double
        let height: Double
        let title: String
        let alt: String
        let previewLabel: String
        let sourceLabel: String
        let credits: [Credit]
    }
    struct Platforms: Decodable, Sendable {
        struct Platform: Decodable, Identifiable, Sendable {
            let id: String
            let name: String
            let note: String
            let status: String
            let statusLabel: String
            let featureText: String
        }
        let title: String
        let copyLinkLabel: String
        let contributeLabel: String
        let repositoryURL: String
        let items: [Platform]
    }
    struct Investment: Decodable, Sendable {
        struct Metric: Decodable, Identifiable, Sendable {
            let id: String
            let value: String
            let label: String
        }
        struct Item: Decodable, Identifiable, Sendable {
            let id: String
            let title: String
            let body: String
            let amount: Int?
            let monthlyAmount: Int?
            let roundingUnit: Int?
            func amount(months: Int) -> Int? { CalmmitCostCalculation.itemAmount(amount, monthlyAmount: monthlyAmount, months: months, roundingUnit: roundingUnit ?? 100) }
        }
        struct Group: Decodable, Identifiable, Sendable {
            let id: String
            let title: String
            let items: [Item]
            func amount(months: Int) -> Int { CalmmitCostCalculation.sumAmounts(items.map { $0.amount(months: months) }) }
        }
        let title: String
        let engineeringTitle: String
        let metrics: [Metric]
        let note: String
        let budgetTitle: String
        let budgetIntro: String
        let groups: [Group]
        let totalTitle: String
        let costNote: String
        func total(months: Int) -> Int { CalmmitCostCalculation.sumAmounts(groups.map { $0.amount(months: months) }) }
    }
    let desktopDownloadURL: String
    let repositoryURL: String
    let sources: [Source]
    let schedule: Schedule
    let languages: [String: Copy]

    func copy(language: AppLanguage) -> Copy {
        let key = language == .english ? "en" : (language == .chinese ? "zh-CN" : "zh-TW")
        return languages[key]!
    }
    static func load(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "AboutContent", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    static func money(_ amount: Int?, language: AppLanguage) -> String {
        guard let amount else { return language.text("Not totaled", "暂未核算") }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return language.text("~¥", "约¥") + (formatter.string(from: NSNumber(value: amount)) ?? String(amount))
    }
}
