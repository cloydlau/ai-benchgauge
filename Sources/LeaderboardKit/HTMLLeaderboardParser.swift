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
                logoURL: artificialAnalysisLogoURL(from: logoPath),
                openness: ModelOpenness.fromSource(object),
                taskCostUSD: number((object["intelligenceIndexCostPerTask"] as? [String: Any])?["cost"] as? [String: Any], key: "total"),
                speed: number(object["timescaleData"] as? [String: Any], key: "medianOutputSpeed")
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
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    logoURL: record.logoURL,
                    openness: record.openness,
                    taskCostUSD: record.taskCostUSD, speed: record.speed
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
                organization: organization,
                openness: ModelOpenness.fromSource(object),
                taskCostUSD: taskCost(from: object), speed: number(object["mean"] as? [String: Any], key: "agentWallTimeSec")
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
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    openness: record.openness,
                    taskCostUSD: record.taskCostUSD, speed: record.speed
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

    public static func valsSWEbench(fromHTML html: String) throws -> Leaderboard {
        func matches(_ pattern: String, _ text: String) throws -> [NSTextCheckingResult] {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        func group(_ result: NSTextCheckingResult, _ index: Int, _ text: String) -> String? {
            guard let range = Range(result.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        func clean(_ value: String) -> String {
            let stripped = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
            return entities.reduce(stripped) { $0.replacingOccurrences(of: $1.key, with: $1.value) }.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard html.contains("Archived Benchmark"),
              let dm = try matches(#"Updated\s+(\d{1,2})/(\d{1,2})/(\d{4})"#, html).first,
              let month = group(dm, 1, html).flatMap(Int.init), let day = group(dm, 2, html).flatMap(Int.init),
              let year = group(dm, 3, html).flatMap(Int.init),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day)),
              date <= Date().addingTimeInterval(300),
              let tm = try matches(#"<table\b[^>]*aria-labelledby="benchmark-leaderboard-title"[^>]*>(.*?)</table>"#, html).first,
              let table = group(tm, 1, html) else { throw ParserError.invalidValsSource }
        let trs = try matches(#"<tr\b[^>]*>(.*?)</tr>"#, table).compactMap { group($0, 1, table) }
        guard let header = trs.first else { throw ParserError.invalidValsSource }
        let headers = try matches(#"<th\b[^>]*>(.*?)</th>"#, header).compactMap { group($0, 1, header).map(clean) }
        guard headers == ["Rank", "Model", "Harness", "Score", "Cost / Test", "Tokens / Test", "Duration / Test"] else { throw ParserError.invalidValsSource }
        var entries: [LeaderboardEntry] = []
        for row in trs.dropFirst() {
            let cells = try matches(#"<t[dh]\b[^>]*>(.*?)</t[dh]>"#, row).compactMap { group($0, 1, row) }
            guard cells.count == 7, let rank = Int(clean(cells[0])), rank == entries.count + 1,
                  let sm = try matches(#"^(\d+(?:\.\d+)?)%$"#, clean(cells[3])).first,
                  let score = group(sm, 1, clean(cells[3])).flatMap(Double.init), score <= 100,
                  let lm = try matches(#"href="/models/([a-zA-Z0-9_.-]+)""#, cells[1]).first,
                  let slug = group(lm, 1, cells[1]) else { throw ParserError.invalidValsSource }
            let model = clean(cells[1]), harness = clean(cells[2]), costText = clean(cells[4]), duration = clean(cells[6])
            guard !model.isEmpty, !harness.isEmpty else { throw ParserError.invalidValsSource }
            let cost = try matches(#"^\$(\d+(?:\.\d+)?)$"#, costText).first.flatMap { group($0, 1, costText).flatMap(Double.init) }
            var speed: Double? = nil
            if let d = try matches(#"^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?$"#, duration).first {
                let hours = group(d, 1, duration).flatMap(Double.init) ?? 0
                let minutes = group(d, 2, duration).flatMap(Double.init) ?? 0
                let seconds = group(d, 3, duration).flatMap(Double.init) ?? 0
                let total = hours * 3600 + minutes * 60 + seconds
                if total > 0 { speed = total }
            }
            let owner = slug.split(separator: "_", maxSplits: 1).first.map(String.init)
            entries.append(LeaderboardEntry(rank: rank, name: "\(model) · \(harness)", score: score, modelID: "vals:\(slug):\(harness)", organization: owner, taskCostUSD: cost, speed: speed))
        }
        guard entries.count >= 20 else { throw ParserError.invalidValsSource }
        return Leaderboard(kind: .valsSWEbench, title: "Vals AI · SWE-bench Verified", sourceUpdatedAt: date, sourceNote: "Archived · SWE-bench Verified", entries: entries)
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

    public static func artificialAnalysisMediaVariant(fromHTML html: String, kind: LeaderboardKind) throws -> Leaderboard {
        let title: String
        switch kind {
        case .artificialAnalysisImageEditing: title = "Artificial Analysis | 图片编辑"
        case .artificialAnalysisImageToVideo: title = "Artificial Analysis | 图生视频"
        case .artificialAnalysisVideoEditing: title = "Artificial Analysis | 视频编辑"
        case .artificialAnalysisSpeechProviderVoice: title = "Artificial Analysis | 文字转语音 · 原生声音"
        case .artificialAnalysisSpeechControlledVoice: title = "Artificial Analysis | 文字转语音 · 受控声音"
        default: throw ParserError.notEnoughArtificialAnalysisRecords(0)
        }
        return try artificialAnalysisArena(fromHTML: html, kind: kind, title: title)
    }

    private static func artificialAnalysisArena(
        fromHTML html: String,
        kind: LeaderboardKind,
        title: String
    ) throws -> Leaderboard {
        var objects = jsonObjects(in: html, containing: "formatted")
        if [.artificialAnalysisImageEditing, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing, .artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice].contains(kind) {
            var primary: [[String: Any]] = []
            var lastRank = 0
            for object in objects {
                guard let formatted = object["formatted"] as? [String: Any], object["values"] is [String: Any] else { continue }
                guard let rank = formatted["rank"] as? Int else { throw ParserError.notEnoughArtificialAnalysisRecords(primary.count) }
                if rank <= lastRank { break }
                guard rank == lastRank + 1 else { throw ParserError.notEnoughArtificialAnalysisRecords(primary.count) }
                lastRank = rank
                primary.append(object)
            }
            objects = primary
        }

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
                logoURL: artificialAnalysisLogoURL(from: logoPath),
                openness: ModelOpenness.fromSource(values),
                taskCostUSD: [.artificialAnalysisTextToImage, .artificialAnalysisImageEditing].contains(kind) ? number(values, key: "pricePer1kImages").map { $0 / 1000 } : kind.isAAVideoCost ? number(values, key: "pricePerMinute") : nil, speed: nil
            )
        }

        guard records.count >= (kind == .artificialAnalysisVideoEditing ? 10 : 20) else {
            throw ParserError.notEnoughArtificialAnalysisRecords(records.count)
        }

        let entries = records
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    logoURL: record.logoURL,
                    openness: record.openness,
                    taskCostUSD: record.taskCostUSD
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

    public static func artificialAnalysisSpeechAgent(fromHTML html: String) throws -> Leaderboard {
        let objects = jsonObjects(in: html, containing: "stsHostModelId")
        var entries: [LeaderboardEntry] = []
        var ranks = Set<Int>(), identifiers = Set<String>()
        for value in objects where (value["sliceKey"] as? String) == "overall" {
            guard let name = value["name"] as? String, !name.isEmpty,
                  let id = value["id"] as? String, !id.isEmpty,
                  let rank = value["rank"] as? Int, rank > 0,
                  let score = number(value, key: "elo"), score.isFinite,
                  ranks.insert(rank).inserted, identifiers.insert(id).inserted else {
                throw ParserError.notEnoughArtificialAnalysisRecords(entries.count)
            }
            entries.append(LeaderboardEntry(rank: rank, name: name, score: score, modelID: id,
                organization: value["creatorName"] as? String, logoURL: artificialAnalysisLogoURL(from: value["logo"] as? String)))
        }
        entries.sort { $0.rank < $1.rank }
        guard entries.count >= 20, entries.enumerated().allSatisfy({ $0.element.rank == $0.offset + 1 }),
              zip(entries, entries.dropFirst()).allSatisfy({ $0.0.score >= $0.1.score }) else {
            throw ParserError.notEnoughArtificialAnalysisRecords(entries.count)
        }
        return Leaderboard(kind: .artificialAnalysisSpeechAgent, title: "Artificial Analysis | 语音对话", entries: entries)
    }

    public static func artificialAnalysisSpeechToText(fromHTML html: String, kind: LeaderboardKind) throws -> Leaderboard {
        guard kind.isErrorRate else { throw ParserError.notEnoughArtificialAnalysisRecords(0) }
        let key = kind == .artificialAnalysisSpeechToTextStreaming ? "aaWerStreamingIndex" : "aaWerIndex"
        let objects = jsonObjects(in: html, containing: key)
        var seen = Set<String>(), records: [(name: String, id: String, rate: Double, organization: String?, logo: URL?, openness: ModelOpenness?)] = []
        for value in objects {
            guard let model = value["model"] as? [String: Any], let host = value["host"] as? [String: Any],
                  let id = value["id"] as? String, !id.isEmpty,
                  let name = (value["displayLabel"] ?? value["displayName"] ?? value["name"]) as? String, !name.isEmpty,
                  let rate = number(value, key: key), rate.isFinite, (0...1).contains(rate), seen.insert(id).inserted else { continue }
            let openness: ModelOpenness? = (model["openWeights"] as? Bool).map { $0 ? .open : .closed }
            records.append((name, id, rate, host["name"] as? String, artificialAnalysisLogoURL(from: value["logo"] as? String), openness))
        }
        guard records.count >= 20 else { throw ParserError.notEnoughArtificialAnalysisRecords(records.count) }
        records.sort { $0.rate == $1.rate ? $0.name < $1.name : $0.rate < $1.rate }
        let entries = records.enumerated().map { index, record in
            LeaderboardEntry(rank: index + 1, name: record.name, score: record.rate * 100, modelID: record.id,
                organization: record.organization, logoURL: record.logo, openness: record.openness)
        }
        return Leaderboard(kind: kind, title: "Artificial Analysis | 语音转文字", entries: entries)
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
                organization: organization,
                openness: ModelOpenness.fromSource(object)
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
            .enumerated()
            .map { index, record in
                LeaderboardEntry(
                    rank: index + 1,
                    name: record.name,
                    score: record.score,
                    modelID: record.modelID,
                    organization: record.organization,
                    openness: record.openness
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
        case invalidValsSource
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
        let openness: ModelOpenness?
        let taskCostUSD: Double?
        let speed: Double?
    }

    private static func number(_ object: [String: Any]?, key: String) -> Double? {
        guard let raw = object?[key] as? NSNumber, String(cString: raw.objCType) != "c" else { return nil }
        let value = raw.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    private static func taskCost(from object: [String: Any]) -> Double? {
        guard let raw = (object["mean"] as? [String: Any])?["costUsd"] as? NSNumber,
              String(cString: raw.objCType) != "c" else { return nil }
        let value = raw.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    private struct ParsedCodingAgentRecord: Sendable {
        let name: String
        let score: Double
        let modelID: String?
        let organization: String?
        let openness: ModelOpenness?
        let taskCostUSD: Double?
        let speed: Double?
    }

    private struct ParsedArenaRecord: Sendable {
        let name: String
        let score: Double
        let modelID: String?
        let organization: String?
        let openness: ModelOpenness?
    }

    static func artificialAnalysisLogoURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        let base = URL(string: "https://artificialanalysis.ai")!
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    static func jsonObjects(
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

    static func rscPayload(in html: String) -> String {
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

            // A truncated server payload may have no closing quote.
            guard index < html.endIndex else { break }
            searchStart = html.index(after: index)
        }

        return payloads.joined(separator: "\n")
    }

    static func unescapedRSCJSON(_ value: String) -> String {
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

    static func artificialAnalysisVersion(fromHTML html: String) -> String? {
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
    /// Only the Coding Agent Index ships that stamp today; the intelligence,
    /// image, and video boards expose no batch time, so they stay `nil`.
    private static func artificialAnalysisDataUpdatedAt(fromHTML html: String) -> Date? {
        jsonStringValues(in: html, afterKey: "materializedAt").compactMap(iso8601Date).max()
    }

    /// Reads escaped JSON strings straight out of the server payload, so a value
    /// nested below the leaderboard rows stays reachable.
    static func jsonStringValues(in html: String, afterKey key: String) -> [String] {
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

    static func iso8601Date(_ value: String) -> Date? {
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
