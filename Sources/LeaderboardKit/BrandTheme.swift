#if canImport(SwiftUI)
import SwiftUI

/// Functional colors stay solid for legibility; reflection bands are reserved
/// for decorative selection surfaces and the brand artwork.
public enum BrandTheme {
    public static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? rgb(209, 220, 232) : rgb(65, 77, 92)
    }

    public static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? rgb(16, 18, 22) : rgb(244, 245, 247)
    }

    public static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? rgb(27, 31, 38) : .white
    }

    public static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? rgb(39, 46, 56) : rgb(231, 234, 240)
    }

    public static func selection(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: scheme == .dark
            ? [rgb(74, 85, 100), rgb(47, 55, 67), rgb(59, 69, 83)]
            : [.white, rgb(225, 230, 237), rgb(241, 244, 248)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
#endif
