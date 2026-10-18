#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import LeaderboardKit

@MainActor
struct BrandThemeTests {
    @Test func functionalColorsStayReadableAndSelectionRetainsReflection() throws {
        _ = NSApplication.shared
        var selections: [Data] = []
        for scheme in [ColorScheme.light, .dark] {
            let accent = try luminance(BrandTheme.accent(for: scheme))
            let background = try luminance(BrandTheme.background(for: scheme))
            let card = try luminance(BrandTheme.card(for: scheme))
            let surface = try luminance(BrandTheme.surface(for: scheme))
            for base in [background, card, surface] {
                #expect((max(accent, base) + 0.05) / (min(accent, base) + 0.05) >= 4.5)
            }
            #expect(abs(surface - background) > 0.01)
            let image = try #require(ImageRenderer(content: Rectangle()
                .fill(BrandTheme.selection(for: scheme)).frame(width: 80, height: 40)).cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let highlight = try #require(bitmap.colorAt(x: 5, y: 5))
            let middle = try #require(bitmap.colorAt(x: 40, y: 20))
            #expect(abs(try luminance(Color(nsColor: highlight)) - luminance(Color(nsColor: middle))) > 0.01)
            selections.append(try #require(image.dataProvider?.data) as Data)
        }
        #expect(selections[0] != selections[1])
    }

    private func luminance(_ color: Color) throws -> Double {
        let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
#endif
