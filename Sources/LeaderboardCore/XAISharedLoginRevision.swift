import Foundation

/// Cheap, noncredential metadata. Atomic replacements and removal change the
/// revision even when a new login has the same byte length as the previous one.
/// A change in shared-token ownership also wakes the existing login watcher.
public struct XAISharedLoginRevision: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date?
    public let fileNumber: UInt64?
    public let size: UInt64?
    public let refreshAllowed: Bool
    public init(url: URL) {
        self.init(url: url, refreshAllowed: XAILoginStore.isAppManaged(url) || !CCSwitchProcess.isRunning())
    }
    public init(url: URL, refreshAllowed: Bool) {
        self.refreshAllowed = refreshAllowed
        path = PlatformPaths.fileSystemPath(url)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        modifiedAt = attributes?[.modificationDate] as? Date
        fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        size = (attributes?[.size] as? NSNumber)?.uint64Value
    }
}
