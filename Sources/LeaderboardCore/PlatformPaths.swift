import Foundation
public enum PlatformPaths {
    public static func fileSystemPath(_ url: URL) -> String {
        #if os(Windows)
        return url.withUnsafeFileSystemRepresentation { pointer in
            pointer.map { String(cString: $0) } ?? url.path
        }
        #else
        return url.path(percentEncoded: false)
        #endif
    }
    public static var applicationSupport: URL {
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment["LOCALAPPDATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "AppData/Local")
        return root.appending(path: "AI-BenchGauge", directoryHint: .isDirectory)
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/AI-BenchGauge", directoryHint: .isDirectory)
        #endif
    }
    static func restrictFile(_ url: URL, permissions: Int) throws {
        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        #endif
        // On Windows files inherit the owning user's profile ACL, not POSIX modes.
    }
}
