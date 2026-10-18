#if canImport(SwiftUI)
import SwiftUI

/// Neutral silver reflection bands matching the polished-platinum brand mark.
/// Light surfaces use deeper steel so the thin letter strokes remain readable.
struct BrandTitleGradient: ShapeStyle {
    @Environment(\.colorScheme) private var colorScheme

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let dark = environment.colorScheme == .dark
        return LinearGradient(
            stops: dark
                ? [.init(color: Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255), location: 0),
                   .init(color: Color(red: 165 / 255, green: 175 / 255, blue: 188 / 255), location: 0.42),
                   .init(color: Color(red: 224 / 255, green: 230 / 255, blue: 238 / 255), location: 0.5),
                   .init(color: Color(red: 141 / 255, green: 153 / 255, blue: 168 / 255), location: 1)]
                : [.init(color: Color(red: 48 / 255, green: 57 / 255, blue: 69 / 255), location: 0),
                   .init(color: Color(red: 136 / 255, green: 148 / 255, blue: 162 / 255), location: 0.42),
                   .init(color: Color(red: 65 / 255, green: 77 / 255, blue: 92 / 255), location: 0.5),
                   .init(color: Color(red: 108 / 255, green: 120 / 255, blue: 136 / 255), location: 1)],
            startPoint: .top, endPoint: .bottom)
    }
}
#endif
