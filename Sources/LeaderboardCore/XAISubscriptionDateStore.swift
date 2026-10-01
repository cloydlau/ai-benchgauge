import Foundation

/// Cache of subscription dates obtained from the API for the selected login.
/// Manual dates and usage resets never enter this store.
public struct XAISubscriptionDateStore: Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let accountID: String
        public let periodEnd: Date
        public let source: ParsedQuotaDateSource

        public init(accountID: String, periodEnd: Date, source: ParsedQuotaDateSource) {
            self.accountID = accountID
            self.periodEnd = periodEnd
            self.source = source
        }
    }

    public let fileURL: URL
    public init(fileURL: URL = PlatformPaths.applicationSupport.appending(path: "xai-subscription-dates.json")) {
        self.fileURL = fileURL
    }

    public func record(accountID: String, now: Date) -> Record? {
        guard let record = records().first(where: { $0.accountID == accountID }),
              record.periodEnd.timeIntervalSince1970.isFinite,
              record.periodEnd > now else { return nil }
        return record
    }

    public func save(_ record: Record) throws {
        guard !record.accountID.isEmpty, record.periodEnd.timeIntervalSince1970.isFinite else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        var values = records().filter { $0.accountID != record.accountID }
        values.append(record)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(values)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try PlatformPaths.restrictFile(fileURL, permissions: 0o600)
    }

    private func records() -> [Record] {
        guard let data = try? Data(contentsOf: fileURL), data.count <= 1_048_576 else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        // Drop legacy hand-entered records individually, retaining only API
        // cache records. They must never become a fallback for a failed query.
        return values.compactMap { value in
            guard value["source"] as? String == ParsedQuotaDateSource.cached.rawValue,
                  let encoded = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? decoder.decode(Record.self, from: encoded)
        }
    }
}
