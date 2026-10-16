import Foundation

/// Feature labels and platform availability stay consistent across native views.
public enum AppFeatureCopy {
    public static func subtitle(language: AppLanguage) -> String {
        language.text("Dual boards & quota tracking", "双榜对照 & 余量追踪")
    }
    public static func subtitleRows(language: AppLanguage) -> [String] {
        guard language == .english else { return [subtitle(language: language)] }
        let parts = subtitle(language: language).components(separatedBy: " & ")
        return [parts[0] + " &", parts[1]]
    }
    public static func quotaTitle(language: AppLanguage) -> String {
        language.text("Quota tracking", "余量追踪")
    }
    public static func quotaHelpLabel(language: AppLanguage) -> String {
        language.text("About quota tracking", "了解余量追踪")
    }
    public static func quotaMessage(language: AppLanguage) -> String {
        language.text(
            "Quota tracking is available in AI BenchGauge for Mac and Windows. Open the desktop app to view your models’ remaining quotas and usage progress.",
            "余量追踪目前在 Mac 和 Windows 版提供，可集中查看模型的剩余额度与使用进度。请在电脑上打开 AI 天梯使用这项功能。"
        )
    }
}
