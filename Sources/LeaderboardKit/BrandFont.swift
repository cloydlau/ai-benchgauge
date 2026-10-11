#if canImport(CoreText)
import CoreText
import Foundation

/// The same offline Chinese title glyphs are used by the Mac and iOS interfaces.
public enum BrandFont {
    public static let chineseName: String = {
        if let url = resource("BenchGaugeCalligraphy", extension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return "BenchGaugeCalligraphy-Regular"
    }()

    public static var licenseText: String {
        guard let url = resource("Long-Cang-OFL", extension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func resource(_ name: String, extension suffix: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: suffix, subdirectory: "Fonts") {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: suffix, subdirectory: "Fonts")
    }
}
#endif
