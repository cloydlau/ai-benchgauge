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
            ? "採用最新 overall 類別，文字榜啟用風格控制。保留原始分數與模型排名，提供篩選、公司彙總、顯示捨入及中繼資料規範化。獨立應用，無 Arena 背書。"
            : language.text("Latest overall category; text uses style control. Original scores and model ranks retained; filtering, company aggregation, rounded display and metadata normalization applied. Independent app; no Arena endorsement.",
                            "采用最新 overall 类别，文本榜启用风格控制。保留原始分数与模型排名，提供筛选、公司聚合、显示舍入及元数据规范化。独立应用，无 Arena 背书。")
        return [credit, sourceURL + " · " + licenseURL, changes].joined(separator: "\n")
    }
}
