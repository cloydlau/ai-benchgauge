import Foundation

/// Official Epoch ECI CSV. Scores are an unbounded index, not percentages.
public enum EpochECIParser {
    public static func parse(_ csv: String, fetchedAt: Date = Date()) throws -> Leaderboard {
        let records = try rows(csv)
        guard let header = records.first, Set(header).count == header.count,
              ["Model", "Display name", "eci", "Organization", "Country (of organization)", "Accessibility group"]
                .allSatisfy(header.contains) else { throw URLError(.cannotParseResponse) }
        var seen = Set<String>()
        var entries: [LeaderboardEntry] = []
        for row in records.dropFirst() {
            guard row.count == header.count else { throw URLError(.cannotParseResponse) }
            let value = Dictionary(uniqueKeysWithValues: zip(header, row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            let modelID = value["Model"]!, display = value["Display name"]!, organization = value["Organization"]!
            let name = display.isEmpty ? modelID : display
            guard !modelID.isEmpty, !name.isEmpty, modelID.count <= 256, name.count <= 256, organization.count <= 256,
                  !(modelID + name + organization).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  let score = Double(value["eci"]!), score.isFinite, abs(score) <= 100_000,
                  seen.insert(modelID).inserted else { throw URLError(.cannotParseResponse) }
            let openness: ModelOpenness? = switch value["Accessibility group"]! {
            case "Open weights": .open
            case "Closed weights": .closed
            default: nil
            }
            let sourceCountry = value["Country (of organization)"]!
            let code = OrganizationCountry(regionCode: sourceCountry)?.regionCode ?? countryNames[sourceCountry.lowercased()]
            let key = OrganizationLogoCatalog.developerKey(organization: organization, modelName: name, modelID: modelID)
            let country = code.flatMap { code in key.map { OrganizationCountryMetadata(key: $0, countryCode: code, sourceURL: "https://epoch.ai/eci") } }
            entries.append(LeaderboardEntry(rank: 0, name: name, score: score, modelID: modelID,
                organization: organization.isEmpty ? nil : organization, openness: openness, developerCountry: country))
        }
        guard (20...5000).contains(entries.count) else { throw URLError(.cannotParseResponse) }
        entries.sort { $0.score == $1.score ? $0.name.precomposedStringWithCanonicalMapping < $1.name.precomposedStringWithCanonicalMapping : $0.score > $1.score }
        entries = entries.enumerated().map { index, entry in
            LeaderboardEntry(rank: index + 1, name: entry.name, score: entry.score, modelID: entry.modelID,
                organization: entry.organization, openness: entry.openness, developerCountry: entry.developerCountry)
        }
        // Epoch's `date` column is each model's release, not a leaderboard update.
        return Leaderboard(kind: .epochECI, title: "Epoch Capabilities Index", sourceNote: "Epoch AI · ECI",
                           fetchedAt: fetchedAt, entries: entries)
    }

    private static let countryNames: [String: String] = {
        let locale = Locale(identifier: "en_US")
        var result: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            if let country = OrganizationCountry(regionCode: region.identifier),
               let name = locale.localizedString(forRegionCode: region.identifier) { result[name.lowercased()] = country.regionCode }
        }
        result["united states of america"] = "US"
        return result
    }()

    /// Byte delimiters preserve UTF-8 and treat CRLF as a single row ending.
    static func rows(_ source: String) throws -> [[String]] {
        let input = Array((source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source).utf8)
        var result: [[String]] = [], row: [String] = [], field: [UInt8] = []
        var quoted = false, closed = false, index = 0
        while index < input.count {
            let byte = input[index]
            if quoted {
                if byte != 34 { field.append(byte) }
                else if index + 1 < input.count && input[index + 1] == 34 { field.append(34); index += 1 }
                else { quoted = false; closed = true }
            } else if byte == 44 || byte == 10 || byte == 13 {
                row.append(String(decoding: field, as: UTF8.self)); field = []; closed = false
                if byte != 44 {
                    if row.contains(where: { !$0.isEmpty }) { result.append(row) }
                    row = []
                    if byte == 13 && index + 1 < input.count && input[index + 1] == 10 { index += 1 }
                }
            } else if byte == 34 && field.isEmpty && !closed { quoted = true }
            else {
                guard !closed && byte != 34 else { throw URLError(.cannotParseResponse) }
                field.append(byte)
            }
            index += 1
        }
        guard !quoted else { throw URLError(.cannotParseResponse) }
        row.append(String(decoding: field, as: UTF8.self))
        if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        return result
    }
}
