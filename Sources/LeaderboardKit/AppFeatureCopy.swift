import Foundation

/// Feature labels and platform availability stay consistent across native views.
public enum AppFeatureCopy {
    public static func subtitle(language: AppLanguage) -> String {
        subtitleRows(language: language).joined(separator: language == .english ? " " : "")
    }
    public static func subtitleRows(language: AppLanguage) -> [String] {
        [language.text("Compare leaderboards to make informed choices;", "多榜对照，选得明白；"),
         language.text("track quotas to know where you stand.", "余量追踪，用得有数。")]
    }
    public static func quotaTitle(language: AppLanguage) -> String {
        language.text("Quota tracking", "余量追踪")
    }
    public static func quotaHelpLabel(language: AppLanguage) -> String {
        language.text("About quota tracking", "了解余量追踪")
    }
    public static func quotaMessage(language: AppLanguage) -> String {
        language.text(
            "Quota tracking is available in the PC edition of AI BenchGauge. Open the desktop app to view your models’ remaining quotas and usage progress.",
            "余量追踪目前在 PC 端提供，可集中查看模型的剩余额度与使用进度。请在电脑上打开 AI 天梯使用这项功能。"
        )
    }
}
