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
                ModelOpennessIcon(open: openness == .open)
                    .stroke(tint, style: StrokeStyle(lineWidth: iconSize / 12, lineCap: .round, lineJoin: .round))
                    .frame(width: iconSize, height: iconSize).frame(width: iconSize * 10 / 9)
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
/// Lucide lock-keyhole icons, matching the mini-program's 24-point viewBox.
/// Both states share the same lock body and bounds; see Resources/Lucide.txt.
public struct ModelOpennessIcon: Shape {
    public let open: Bool

    public init(open: Bool) { self.open = open }

    public func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 3, y: 10, width: 18, height: 12), cornerRadius: 2)
        path.addEllipse(in: CGRect(x: 11, y: 15, width: 2, height: 2))
        path.move(to: CGPoint(x: 7, y: 10))
        path.addLine(to: CGPoint(x: 7, y: 7))
        path.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 7, y: 4.238576), control2: CGPoint(x: 9.238576, y: 2))
        if open {
            path.addCurve(to: CGPoint(x: 16.330127, y: 4.5), control1: CGPoint(x: 13.786328, y: 2), control2: CGPoint(x: 15.436963, y: 2.952995))
        } else {
            path.addCurve(to: CGPoint(x: 17, y: 7), control1: CGPoint(x: 14.761424, y: 2), control2: CGPoint(x: 17, y: 4.238576))
            path.addLine(to: CGPoint(x: 17, y: 10))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

#endif
