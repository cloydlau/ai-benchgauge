import Foundation

/// Official CC BY 4.0 text. Attribution notices stay separate so the about-page
/// license dialog can show the license itself, not the credit or endorsement line.
public enum CCBYLicense {
    struct Document: Decodable, Sendable {
        let canonicalURL: String
        let en: String
        let zh: String
        let zhHant: String

        enum CodingKeys: String, CodingKey {
            case canonicalURL, en, zh
            case zhHant = "zh-Hant"
        }
    }

    // Required distribution resource. Fail at launch if the bundled deed is missing.
    private static let document = try! load(from: BundledResource.url("CC-BY-4.0", extension: "json"))

    static func load(from url: URL) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }

    public static var canonicalURL: String { document.canonicalURL }

    public static func text(language: AppLanguage) -> String {
        switch language {
        case .english: document.en
        case .chinese: document.zh
        case .traditionalChinese: document.zhHant
        }
    }

    public static func vercelText(sourceNote: String?, language: AppLanguage) -> String {
        let note = sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = note?.isEmpty == false ? note! : "© 2026 Vercel. \"AI Gateway Leaderboard Data\" is licensed under CC BY 4.0. To view a copy of this license, visit " + canonicalURL + "\nSource: https://vercel.com/ai-gateway/leaderboards/models"
        return attribution + "\n\n" + text(language: language)
    }

    public static func openRouterText(sourceNote: String?, language: AppLanguage) -> String {
        let note = sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = note?.isEmpty == false ? note! : "Source: OpenRouter (openrouter.ai/rankings).\nLicensed under CC BY 4.0.\n" + canonicalURL
        return attribution + "\n\n" + text(language: language)
    }
}

public enum CloudBaseAttribution {
    public static func text(sourceNote: String?, language: AppLanguage) -> String {
        let explanation = language.text("Tencent CloudBase publishes cumulative token shares for sampled Beijing-time days. It groups model families, includes cached input tokens and does not provide absolute volumes or full sample dates. No open-data license is stated; Tencent retains its rights. This data is not licensed under CC BY 4.0.", "腾讯 CloudBase 公布北京时间抽样统计日的 token 累计占比，按模型系列汇总，包含缓存命中；未公开绝对用量或完整抽样日期。来源未声明开放数据许可，相关权利归腾讯所有，此数据不适用 CC BY 4.0。")
        return explanation + "\n\n" + (sourceNote?.isEmpty == false ? sourceNote! : "Source: Tencent CloudBase\nhttps://docs.cloudbase.net/ai/announcement/model-token-volume")
    }
}
