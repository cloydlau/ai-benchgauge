import Foundation

public enum HTMLLeaderboardParser {
    public static func artificialAnalysis(fromHTML html: String) throws -> Leaderboard {
        let objects = jsonObjects(in: html, containing: "intelligenceIndex")
        var seenRecords = Set<String>()
        let records: [ParsedArtificialAnalysisRecord] = objects.compactMap { object in
            guard
                let name = object["name"] as? String,
                let rawScore = object["intelligenceIndex"] as? Double,
                (object["intelligenceIndexIsEstimated"] as? Bool) != true
            else { return nil }
            let creator = object["creator"] as? [String: Any]
            let modelID = object["slug"] as? String
            let organization = creator?["name"] as? String
            let logoPath = creator?["logo"] as? String
            let key = "\(name)|\(rawScore)"
            guard seenRecords.insert(key).inserted else { return nil }
            return ParsedArtificialAnalysisRecord(
                name: name,
                score: rawScore,
                modelID: modelID,
                organization: organization,
                logoURL: artificialAnalysisLogoURL(from: logoPath)
            )
        }

        guard records.count >= 20 else {
            throw ParserError.notEnoughArtificialAnalysisRecords(records.count)
        }

        let entries = records
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .prefix(20)
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    logoURL: record.logoURL
                )
            }

        let organizationLogoURLs = records.reduce(into: [String: URL]()) { result, record in
            guard let organization = record.organization,
                  let logoURL = record.logoURL else { return }
            result[organization] = logoURL
        }

        return Leaderboard(
            kind: .artificialAnalysis,
            title: "Artificial Analysis Intelligence Index",
            sourceUpdatedAt: artificialAnalysisDataUpdatedAt(fromHTML: html),
            sourceNote: artificialAnalysisVersion(fromHTML: html),
            entries: entries,
            organizationLogoURLs: organizationLogoURLs
        )
    }

    public static func artificialAnalysisCodingAgent(fromHTML html: String) throws -> Leaderboard {
        let objects = jsonObjects(in: html, containing: "indexScore")
        var seenRecords = Set<String>()
        let records: [ParsedCodingAgentRecord] = objects.compactMap { object in
            guard
                let name = object["displayLabel"] as? String,
                let rawScore = object["indexScore"] as? Double,
                seenRecords.insert(name).inserted
            else { return nil }

            let display = object["display"] as? [String: Any]
            let creator = display?["creator"] as? [String: Any]
            let organization = creator?["agent"] as? String
            let modelID = object["hostModelSlug"] as? String
            return ParsedCodingAgentRecord(
                name: name,
                score: rawScore * 100,
                modelID: modelID,
                organization: organization
            )
        }

        guard records.count >= 10 else {
            throw ParserError.notEnoughCodingAgentRecords(records.count)
        }

        let entries = records
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .prefix(20)
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization
                )
            }

        return Leaderboard(
            kind: .artificialAnalysisCodingAgent,
            title: "Artificial Analysis Coding Agent Index",
            sourceUpdatedAt: artificialAnalysisDataUpdatedAt(fromHTML: html),
            sourceNote: artificialAnalysisCodingAgentVersion(fromHTML: html),
            entries: entries
        )
    }

    public static func arenaWebDev(fromHTML html: String) throws -> Leaderboard {
        try arena(fromHTML: html, kind: .codeArenaWebDev, title: "Code Arena | WebDev")
    }

    public static func arenaText(fromHTML html: String) throws -> Leaderboard {
        try arena(fromHTML: html, kind: .arenaText, title: "Arena | Text")
    }

    public static func arenaTextToImage(fromHTML html: String) throws -> Leaderboard {
        try arena(fromHTML: html, kind: .arenaTextToImage, title: "Arena | 文生图")
    }

    public static func arenaTextToVideo(fromHTML html: String) throws -> Leaderboard {
        try arena(fromHTML: html, kind: .arenaTextToVideo, title: "Arena | 文生视频")
    }

    public static func artificialAnalysisTextToImage(fromHTML html: String) throws -> Leaderboard {
        try artificialAnalysisArena(
            fromHTML: html,
            kind: .artificialAnalysisTextToImage,
            title: "Artificial Analysis | 文生图"
        )
    }

    public static func artificialAnalysisTextToVideo(fromHTML html: String) throws -> Leaderboard {
        try artificialAnalysisArena(
            fromHTML: html,
            kind: .artificialAnalysisTextToVideo,
            title: "Artificial Analysis | 文生视频"
        )
    }

    private static func artificialAnalysisArena(
        fromHTML html: String,
        kind: LeaderboardKind,
        title: String
    ) throws -> Leaderboard {
        let objects = jsonObjects(in: html, containing: "formatted")

        var seenRecords = Set<String>()
        let records: [ParsedArtificialAnalysisRecord] = objects.compactMap { object in
            guard
                object["formatted"] is [String: Any],
                let values = object["values"] as? [String: Any],
                let name = values["name"] as? String,
                let score = values["elo"] as? Double
            else { return nil }
            let creator = values["creator"] as? [String: Any]
            let modelID = values["id"] as? String
            let organization = creator?["name"] as? String
            let logoPath = creator?["logo"] as? String
            // These pages embed multiple sub-leaderboards. The primary board is
            // emitted first, so keep the first occurrence of each model.
            let key = modelID ?? name
            guard seenRecords.insert(key).inserted else { return nil }
            return ParsedArtificialAnalysisRecord(
                name: name,
                score: score,
                modelID: modelID,
                organization: organization,
                logoURL: artificialAnalysisLogoURL(from: logoPath)
            )
        }

        guard records.count >= 20 else {
            throw ParserError.notEnoughArtificialAnalysisRecords(records.count)
        }

        let entries = records
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .prefix(20)
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    logoURL: record.logoURL
                )
            }

        let organizationLogoURLs = records.reduce(into: [String: URL]()) { result, record in
            guard let organization = record.organization,
                  let logoURL = record.logoURL else { return }
            result[organization] = logoURL
        }

        return Leaderboard(
            kind: kind,
            title: title,
            sourceUpdatedAt: artificialAnalysisDataUpdatedAt(fromHTML: html),
            entries: entries,
            organizationLogoURLs: organizationLogoURLs
        )
    }

    private static func arena(
        fromHTML html: String,
        kind: LeaderboardKind,
        title: String
    ) throws -> Leaderboard {
        let objects = jsonObjects(in: html, containing: "modelDisplayName")

        var seenRecords = Set<String>()
        let records: [ParsedArenaRecord] = objects.compactMap { object in
            guard
                let name = object["modelDisplayName"] as? String,
                let score = object["rating"] as? Double
            else { return nil }
            let modelID = object["modelKey"] as? String
            let organization = object["modelOrganization"] as? String
            let key = "\(name)|\(score)"
            guard seenRecords.insert(key).inserted else { return nil }
            return ParsedArenaRecord(
                name: name,
                score: score,
                modelID: modelID,
                organization: organization
            )
        }

        guard records.count >= 20 else {
            throw ParserError.notEnoughArenaRecords(records.count)
        }

        let entries = records
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .prefix(20)
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization
                )
            }

        return Leaderboard(
            kind: kind,
            title: title,
            sourceUpdatedAt: arenaVoteCutoff(fromHTML: html),
            entries: entries
        )
    }

    public enum ParserError: Error, Equatable {
        case notEnoughArtificialAnalysisRecords(Int)
        case notEnoughCodingAgentRecords(Int)
        case notEnoughArenaRecords(Int)
        case invalidArenaDate(String)
    }

    private struct ParsedArtificialAnalysisRecord: Sendable {
        let name: String
        let score: Double
        let modelID: String?
        let organization: String?
        let logoURL: URL?
    }

    private struct ParsedCodingAgentRecord: Sendable {
        let name: String
        let score: Double
        let modelID: String?
        let organization: String?
    }

    private struct ParsedArenaRecord: Sendable {
        let name: String
        let score: Double
        let modelID: String?
        let organization: String?
    }

    private static func artificialAnalysisLogoURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        let base = URL(string: "https://artificialanalysis.ai")!
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    private static func jsonObjects(
        in html: String,
        containing marker: String
    ) -> [[String: Any]] {
        let payload = rscPayload(in: html)
        var objectStack: [String.Index] = []
        var snippets: [String] = []
        var inString = false
        var escaped = false
        var index = payload.startIndex

        while index < payload.endIndex {
            let character = payload[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                objectStack.append(index)
            } else if character == "}", !objectStack.isEmpty {
                let start = objectStack.removeLast()
                let snippet = payload[start...index]
                if snippet.contains(marker) {
                    snippets.append(String(snippet))
                }
            }

            index = payload.index(after: index)
        }

        return snippets.compactMap { snippet in
            unescapedRSCJSON(snippet).data(using: .utf8).flatMap { data in
                try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        }
    }

    private static func rscPayload(in html: String) -> String {
        let opener = "self.__next_f.push([1,\""
        var payloads: [String] = []
        var searchStart = html.startIndex

        while let openerRange = html.range(of: opener, range: searchStart..<html.endIndex) {
            var index = openerRange.upperBound
            var escaped = false

            while index < html.endIndex {
                let character = html[index]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    payloads.append(unescapedRSCJSON(String(html[openerRange.upperBound..<index])))
                    break
                }

                index = html.index(after: index)
            }

            searchStart = html.index(after: index)
        }

        return payloads.joined(separator: "\n")
    }

    private static func unescapedRSCJSON(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        var escaped = false

        for character in value {
            if escaped {
                switch character {
                case "\"", "\\", "/":
                    output.append(character)
                case "n":
                    output.append("\n")
                case "r":
                    output.append("\r")
                case "t":
                    output.append("\t")
                default:
                    output.append("\\")
                    output.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                output.append(character)
            }
        }

        return output
    }

    private static func artificialAnalysisVersion(fromHTML html: String) -> String? {
        guard
            let titleRange = html.range(of: "<title>"),
            let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex)
        else { return nil }

        let title = String(html[titleRange.upperBound..<endRange.lowerBound])
        guard
            let versionRange = title.range(of: "v[0-9]+(\\.[0-9]+)*", options: .regularExpression)
        else { return nil }
        return String(title[versionRange])
    }

    private static func artificialAnalysisCodingAgentVersion(fromHTML html: String) -> String? {
        guard
            let versionRange = html.range(
                of: "Artificial Analysis Coding Agent Index v[0-9]+(\\.[0-9]+)*",
                options: .regularExpression
            )
        else { return nil }

        let value = String(html[versionRange])
        return value.replacingOccurrences(of: "Artificial Analysis Coding Agent Index ", with: "")
    }

    private static func arenaVoteCutoff(fromHTML html: String) -> Date? {
        guard
            let value = jsonStringValues(in: html, afterKey: "voteCutoffISOString").first
        else { return nil }
        return iso8601Date(value)
    }

    /// Artificial Analysis stamps each grading batch with `materializedAt`. Every
    /// row on a board repeats the same value, so the newest one marks when the
    /// source regenerated this leaderboard's data, not when this Mac fetched it.
    private static func artificialAnalysisDataUpdatedAt(fromHTML html: String) -> Date? {
        jsonStringValues(in: html, afterKey: "materializedAt").compactMap(iso8601Date).max()
    }

    /// Reads escaped JSON strings straight out of the server payload, so a value
    /// nested below the leaderboard rows stays reachable.
    private static func jsonStringValues(in html: String, afterKey key: String) -> [String] {
        var values: [String] = []
        var searchStart = html.startIndex

        while let keyRange = html.range(of: key, range: searchStart..<html.endIndex) {
            searchStart = keyRange.upperBound
            guard
                let colon = html.range(of: ":", range: keyRange.upperBound..<html.endIndex),
                let openingQuote = html.range(of: "\"", range: colon.upperBound..<html.endIndex),
                let closingQuote = html.range(
                    of: "\"",
                    range: openingQuote.upperBound..<html.endIndex
                )
            else { continue }

            let value = String(html[openingQuote.upperBound..<closingQuote.lowerBound])
            values.append(value.replacingOccurrences(of: "\\", with: ""))
        }

        return values
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }

        // Source timestamps can carry six fractional digits, which the formatter
        // only accepts once they are trimmed down to milliseconds.
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(
            from: value.replacingOccurrences(
                of: "(\\.\\d{3})\\d+",
                with: "$1",
                options: .regularExpression
            )
        )
    }
}
