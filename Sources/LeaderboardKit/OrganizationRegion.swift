import Foundation

/// ISO region codes allow newly discovered developers without an app update.
/// Existing raw values remain compatible with saved country filters.
public struct OrganizationCountry: RawRepresentable, Hashable, CaseIterable, Sendable {
    public let regionCode: String
    private static let legacy = ["china": "CN", "unitedStates": "US", "canada": "CA", "france": "FR", "germany": "DE", "singapore": "SG"]
    private static let validRegions = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && !["EU", "UN", "ZZ", "XA", "XB", "QO"].contains($0) })
    public init?(regionCode: String) {
        let source = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let code = LeaderboardBrandPolicy.countryOverrides[source] ?? source
        guard Self.validRegions.contains(code) else { return nil }
        self.regionCode = code
    }
    public init?(rawValue: String) { self.init(regionCode: Self.legacy[rawValue] ?? rawValue) }
    public var rawValue: String { Self.legacy.first { $0.value == regionCode }?.key ?? regionCode }
    public static let china = Self(regionCode: "CN")!
    public static let unitedStates = Self(regionCode: "US")!
    public static let canada = Self(regionCode: "CA")!
    public static let france = Self(regionCode: "FR")!
    public static let germany = Self(regionCode: "DE")!
    public static let singapore = Self(regionCode: "SG")!
    public static var allCases: [Self] {
        let first: [Self] = [.china, .unitedStates, .canada, .france, .germany, .singapore]
        return first + validRegions.sorted().compactMap(Self.init(regionCode:)).filter { !first.contains($0) }
    }

    public var flagEmoji: String {
        let regionalIndicatorBase: UInt32 = 0x1F1E6
        let scalars = regionCode.utf8.map { byte in
            Unicode.Scalar(regionalIndicatorBase + UInt32(byte - 65))!
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Use the app's China label consistently in filters, hover text, and
    /// accessibility; other country names come from system locale data.
    public func localizedName(language: AppLanguage) -> String {
        localizedName(language: language, localize: { language.locale.localizedString(forRegionCode: $0) })
    }

    func localizedName(language: AppLanguage, localize: (String) -> String?) -> String {
        if self == .china { return language.text("China", "中国") }
        return localize(regionCode) ?? regionCode
    }
}

/// Country of the model developer's headquarters. Coding harnesses follow
/// the lead model, while a company row follows the company's own key.
public enum OrganizationRegion {
    public static func unknownTitle(language: AppLanguage) -> String {
        language.text("Why no country?", "为什么没有国家归属？")
    }

    public static func unknownExplanation(language: AppLanguage) -> String {
        language.text(
            "Country reflects the model developer’s headquarters. Some models are community projects or collaborations, or lack enough reliable information to identify one developer and headquarters. We leave them unassigned rather than guess from the model name, language, base model or hosting provider.",
            "国家归属依据模型开发者的总部所在地。部分模型属于社区项目或多方合作，也可能缺少足够可靠的信息来确认开发者及其总部，因此暂不归属到某个国家。我们不会根据模型名称、语言、基座模型或托管平台猜测归属。")
    }

    public static func country(for entry: LeaderboardEntry) -> OrganizationCountry? {
        if let metadata = entry.developerCountry,
           metadata.key == OrganizationLogoCatalog.developerKey(organization: entry.organization, modelName: entry.name, modelID: entry.modelID),
           let code = metadata.countryCode, let country = OrganizationCountry(regionCode: code) {
            return country
        }
        return country(entry.organization, modelName: entry.name, modelID: entry.modelID)
    }

    public static func country(_ organization: String?, modelName: String? = nil, modelID: String? = nil) -> OrganizationCountry? {
        guard let key = OrganizationLogoCatalog.developerKey(
            organization: organization,
            modelName: modelName, modelID: modelID
        ) else { return nil }
        return LeaderboardBrandPolicy.countryCodes[key].flatMap(OrganizationCountry.init(regionCode:))
    }

    public static func isChinese(_ organization: String?, modelName: String? = nil) -> Bool {
        country(organization, modelName: modelName) == .china
    }
}
