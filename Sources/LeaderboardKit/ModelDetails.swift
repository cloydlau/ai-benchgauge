import Foundation

public struct ModelDetailRow: Codable, Equatable, Sendable {
    public let label: String
    public let value: String
    public let url: String?
}
public struct ModelDetailSection: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String?
    public let rows: [ModelDetailRow]
}
public enum ModelDetails {
    public static func syncTime(_ value: String, timeZone: TimeZone = .current) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = parser.date(from: value)
        parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: value) else { return value.isEmpty ? "—" : value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private static let labels: [String: [String]] = {
        let executableResource = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ModelDetailLabels.json")
        return loadLabels(at: try? BundledResource.url("ModelDetailLabels", extension: "json", executable: executableResource))
    }()
    static func loadLabels(at url: URL?) -> [String: [String]] {
        guard let url, let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return value
    }
    public static func text(_ key: String, language: AppLanguage) -> String {
        localizedText(key, language: language, labels: labels)
    }
    static func localizedText(_ key: String, language: AppLanguage, labels: [String: [String]]) -> String {
        let index = language == .english ? 0 : language == .traditionalChinese ? 2 : 1
        return labels[key].flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? key.replacingOccurrences(of: "_", with: " ")
    }
    static func map<T: Encodable>(_ value: T) -> [String: ModelDetailValue] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        return (try? JSONDecoder().decode([String: ModelDetailValue].self, from: data)) ?? [:]
    }
    public static func sections(for entry: LeaderboardEntry, language: AppLanguage, timeZone: TimeZone = .current) -> [ModelDetailSection] {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 12
        return sections(for: entry, language: language, formatter: formatter, timeZone: timeZone)
    }
    static func sections(for entry: LeaderboardEntry, language: AppLanguage, formatter: NumberFormatter, timeZone: TimeZone = .current) -> [ModelDetailSection] {
        guard let model = entry.modelMetadata, model.source == "models.dev" else { return [] }
        let tr: (String) -> String = { text($0, language: language) }
        func scalar(_ value: ModelDetailValue, money: Bool = false) -> String? {
            switch value {
            case .string(let s): return s.isEmpty ? nil : (labels[s] == nil ? s : tr(s))
            case .number(let n): return (money ? "$" : "") + (formatter.string(from: NSNumber(value: n)) ?? String(n))
            case .bool(let b): return tr(b ? "true" : "false")
            default: return nil
            }
        }
        func rows(_ value: ModelDetailValue, prefix: [String] = [], money: Bool = false) -> [ModelDetailRow] {
            if let string = scalar(value, money: money) {
                let url = URL(string: string).flatMap { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil ? string : nil }
                return [ModelDetailRow(label: prefix.joined(separator: " · "), value: string, url: url)]
            }
            switch value {
            case .object(let dict):
                return dict.keys.sorted().flatMap { key in rows(dict[key]!, prefix: prefix + [tr(key)], money: money && key != "tier") }
            case .array(let array):
                let values = array.compactMap { scalar($0, money: money) }
                if values.count == array.count && !values.isEmpty { return [ModelDetailRow(label: prefix.joined(separator: " · "), value: values.joined(separator: " · "), url: nil)] }
                return array.enumerated().flatMap { index, item in rows(item, prefix: prefix + [String(index + 1)], money: money) }
            default: return []
            }
        }
        var result: [ModelDetailSection] = []
        func add(_ id: String, _ title: String, _ values: [ModelDetailRow], summary: String? = nil) {
            if !values.isEmpty { result.append(ModelDetailSection(id: id, title: title, summary: summary, rows: values)) }
        }
        var attributes = model.attributes ?? [:]
        var general = map(model).filter { ["id", "name", "license", "releaseDate", "lastUpdated", "openWeights"].contains($0.key) }
        if general["license"] == nil { general["license"] = .string(tr("unknown")) }
        for key in ["description", "family", "type", "knowledge"] { if let v = attributes.removeValue(forKey: key) { general[key] = v } }
        add("general", tr("general"), rows(.object(general)))
        add("limits", tr("limit"), rows(.object(map(model.limit))))
        var capabilities: [String: ModelDetailValue] = [:]
        for key in ["attachment", "reasoning", "tool_call", "structured_output", "temperature"] {
            if let v = attributes.removeValue(forKey: key) { capabilities[key] = v }
        }
        add("capabilities", tr("capabilities"), rows(.object(capabilities)))
        if let v = attributes.removeValue(forKey: "modalities") { add("modalities", tr("modalities"), rows(v)) }
        for key in ["links", "weights"] { if let v = attributes.removeValue(forKey: key) { add(key, tr(key), rows(v)) } }
        if case .array(let benchmarks) = attributes.removeValue(forKey: "benchmarks") {
            for (index, benchmark) in benchmarks.enumerated() {
                guard case .object(var values) = benchmark else { continue }
                let title = values.removeValue(forKey: "name").flatMap { scalar($0) } ?? String(index + 1)
                add("benchmark-\(index)", tr("benchmark") + " · " + title, rows(.object(values)))
            }
        }
        add("additional", tr("additional"), rows(.object(attributes)))
        for (index, offer) in model.offers.enumerated() {
            var values = rows(.string(offer.modelID), prefix: [tr("modelID")])
            if let status = offer.status { values += rows(.string(status), prefix: [tr("status")]) }
            values += rows(.object(map(offer.limit)), prefix: [tr("limit")])
            var summary = tr("unknown")
            if let cost = offer.cost {
                values += rows(.object(map(cost)), prefix: [tr("cost")], money: true)
                summary = tr("input") + " $" + (formatter.string(from: NSNumber(value: cost.input)) ?? "")
                    + " · " + tr("output") + " $" + (formatter.string(from: NSNumber(value: cost.output)) ?? "") + " · " + tr("pricing")
            } else { values.append(ModelDetailRow(label: tr("cost"), value: tr("unknown"), url: nil)) }
            values += rows(.object(offer.attributes ?? [:]))
            add("provider-\(index)", offer.providerName, values, summary: summary)
        }
        add("source", tr("provenance"), [ModelDetailRow(label: tr("source"), value: "models.dev · MIT", url: "https://models.dev"),
            ModelDetailRow(label: tr("fetchedAt"), value: syncTime(model.fetchedAt, timeZone: timeZone), url: nil), ModelDetailRow(label: "", value: tr("licenseNote"), url: nil)])
        return result
    }
}
