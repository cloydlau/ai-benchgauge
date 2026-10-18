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
            max(0, Int(floor((date.timeIntervalSince1970 * 1000 - startedAt) / meanMonthMilliseconds + 0.5)))
        }
    }
    struct Copy: Decodable, Sendable {
        let descriptionLines: [String]
        let investment: Investment
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
            func amount(months: Int) -> Int? { monthlyAmount.map { $0 * months } ?? amount }
        }
        struct Group: Decodable, Identifiable, Sendable {
            let id: String
            let title: String
            let items: [Item]
            func amount(months: Int) -> Int { items.reduce(0) { $0 + ($1.amount(months: months) ?? 0) } }
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
        func total(months: Int) -> Int { groups.reduce(0) { $0 + $1.amount(months: months) } }
    }
    let desktopDownloadURL: String
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
