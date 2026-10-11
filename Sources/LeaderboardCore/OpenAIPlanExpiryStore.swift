import Foundation

/// Only account-matched entitlement dates obtained from ChatGPT are retained.
/// A temporary check failure must not erase a still-future subscription date.
public struct OpenAIPlanExpiryStore: Sendable {
    private static let writeLock = NSLock()
    private struct Record: Codable {
        let accountID: String
        let expiresAt: Date
    }

    public let fileURL: URL

    public init(fileURL: URL = PlatformPaths.applicationSupport.appending(path: "openai-plan-expiry.json")) {
        self.fileURL = fileURL
    }

    public func cachedWindow(accountID: String, now: Date) -> ParsedQuotaWindow? {
        guard let record = records().first(where: { $0.accountID == accountID }),
              record.expiresAt.timeIntervalSince1970.isFinite, record.expiresAt > now else { return nil }
        return ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0,
                                 resetsAt: record.expiresAt, dateSource: .cached)
    }

    /// A successful check without an entitlement date invalidates the old date.
    public func save(accountID: String, expiresAt: Date?) throws {
        guard !accountID.isEmpty else { return }
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        var values = records().filter { $0.accountID != accountID }
        if let expiresAt, expiresAt.timeIntervalSince1970.isFinite {
            values.append(Record(accountID: accountID, expiresAt: expiresAt))
        }
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
        return (try? decoder.decode([Record].self, from: data)) ?? []
    }
}
