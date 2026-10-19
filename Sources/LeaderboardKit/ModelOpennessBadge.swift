#if canImport(SwiftUI)
import SwiftUI

/// Use distinct lock symbols and accessible status text, including in compact layouts.
public struct ModelOpennessBadge: View {
    public let openness: ModelOpenness?
    public let language: AppLanguage
    private let showsTitle: Bool
    private let scheme: ColorScheme?
    private let identifier: String
    private let iconSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(_ openness: ModelOpenness?, language: AppLanguage,
                colorScheme: ColorScheme? = nil, showsTitle: Bool = true,
                accessibilityIdentifier: String = "", iconSize: CGFloat = 9) {
        self.openness = openness
        self.language = language
        self.scheme = colorScheme
        self.showsTitle = showsTitle
        self.identifier = accessibilityIdentifier
        self.iconSize = iconSize
    }

    private var dark: Bool { (scheme ?? colorScheme) == .dark }
    public static func tint(for openness: ModelOpenness?, dark: Bool) -> Color {
        if openness == .open {
            return dark ? Color(red: 119 / 255, green: 217 / 255, blue: 161 / 255)
                : Color(red: 24 / 255, green: 137 / 255, blue: 102 / 255)
        }
        return dark ? Color(red: 184 / 255, green: 190 / 255, blue: 199 / 255)
            : Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
    }
    private var tint: Color { Self.tint(for: openness, dark: dark) }

    public var body: some View {
        if let openness {
            HStack(spacing: 3) {
                Image(systemName: openness == .open ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: iconSize, weight: .medium)).frame(width: iconSize * 10 / 9)
                    .accessibilityHidden(true)
                if showsTitle { Text(openness.title(language: language)) }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, showsTitle ? 4 : 0).padding(.vertical, showsTitle ? 3 : 0)
            .background(tint.opacity(showsTitle ? (dark ? 0.16 : 0.10) : 0), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(openness.title(language: language))
            .accessibilityIdentifier(identifier)
        } else {
            Text("—").font(.caption)
                .foregroundStyle(Color(white: dark ? 0.6 : 0.5))
                .accessibilityIdentifier(identifier)
        }
    }
}
#endif
