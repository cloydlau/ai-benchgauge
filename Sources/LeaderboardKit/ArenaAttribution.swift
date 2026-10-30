import Foundation

public enum ArenaAttribution {
    public static let credit = "Arena · Arena Leaderboard Dataset · CC BY 4.0"
    public static let sourceURL = "https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset"
    public static let licenseURL = "https://creativecommons.org/licenses/by/4.0/"
    public static func applies(_ board: Leaderboard?) -> Bool {
        board?.kind.sourcePrefix == "Arena" && board?.sourceNote?.contains(sourceURL) == true
    }
    public static func fullText(language: AppLanguage) -> String {
        let changes = language == .traditionalChinese
            ? "採用所選類別及計分版本的最新榜單。保留原始分數與模型排名，提供篩選、公司彙總、顯示捨入及中繼資料規範化。"
            : language.text("Latest selected category and scoring variant. Original scores and model ranks retained; filtering, company aggregation, rounded display and metadata normalization applied.",
                            "采用所选类别和计分版本的最新榜单。保留原始分数与模型排名，提供筛选、公司聚合、显示舍入及元数据规范化。")
        return [credit, sourceURL + " · " + licenseURL, changes].joined(separator: "\n")
    }
}
