import Foundation

public enum PurchaseLinkSite: Hashable, Sendable {
    case mainlandChina, international, universal
}

public struct PurchaseLink: Identifiable, Hashable, Sendable {
    public let label: String
    public let url: URL
    public let site: PurchaseLinkSite

    public init(label: String, url: URL, site: PurchaseLinkSite = .universal) {
        self.label = label
        self.url = url
        self.site = site
    }

    public var id: String { "\(label)|\(url.absoluteString)" }
}

public struct PurchaseLinks: Hashable, Sendable {
    public let codingPlan: [PurchaseLink]
    public let payAsYouGo: [PurchaseLink]

    public init(codingPlan: [PurchaseLink] = [], payAsYouGo: [PurchaseLink] = []) {
        self.codingPlan = codingPlan
        self.payAsYouGo = payAsYouGo
    }

    public var isEmpty: Bool {
        codingPlan.isEmpty && payAsYouGo.isEmpty
    }
}

public enum PurchaseLinkCatalog {
    /// Simplified Chinese prefers mainland sites. All other interface
    /// languages prefer international sites; a sole .cn URL still opens.
    public static func preferredLink(from links: [PurchaseLink], language: AppLanguage) -> PurchaseLink? {
        guard !links.isEmpty else { return nil }
        if language == .chinese {
            return links.first { $0.site == .mainlandChina || isChineseDomain($0.url) }
                ?? links.first
        }
        return links.first { $0.site == .international }
            ?? links.first { $0.site == .universal && !isChineseDomain($0.url) }
            ?? links.first
    }

    private static func isChineseDomain(_ url: URL) -> Bool {
        url.host?.lowercased().hasSuffix(".cn") == true
    }

    /// Resolves purchase pages for a leaderboard row.
    /// `modelName` is only used when the source omits `organization` (Devin).
    public static func links(forOrganization organization: String?, modelName: String? = nil, category: LeaderboardCategory = .general) -> PurchaseLinks {
        let variants = PurchaseLinkData.vendors[resolvedKey(organization: organization, modelName: modelName)]
        return variants?[category.rawValue] ?? variants?["default"] ?? PurchaseLinks()
    }

    private static func resolvedKey(organization: String?, modelName: String?) -> String {
        let organizationKey = normalizedOrganization(organization ?? "")
        if !organizationKey.isEmpty {
            return organizationKey
        }
        return inferredKey(from: modelName ?? "")
    }

    /// Devin rows on the coding-agent board have no organization.
    private static func inferredKey(from modelName: String) -> String {
        let normalized = normalizedOrganization(modelName)
        if normalized.hasPrefix("devin") {
            return "devin"
        }
        return ""
    }

    enum URLValidationError: Error { case invalid }

    static func validatedURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              urlString.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw URLValidationError.invalid
        }
        return url
    }

    private static func normalizedOrganization(_ organization: String) -> String {
        let words = organization
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()

        return PurchaseLinkData.aliases[words] ?? words
    }
}
