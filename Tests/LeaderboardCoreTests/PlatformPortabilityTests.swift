import Foundation
import Testing
@testable import LeaderboardCore
#if os(Windows)
import CPlatformSupport
#endif
struct PlatformPortabilityTests {
    @Test func profileDirectoryKeepsTheSameHashOnBothSystems() async {
        let source = OpenAIManagedQuotaSource(rootURL: FileManager.default.temporaryDirectory)
        let profile = await source.profileURL(for: "fixture")
        #expect(profile.lastPathComponent == "f16d05ec6b29248d2c61adb1e9263f78e4f7bace1b955014a2d17872cfe4064d")
    }
    #if os(Windows)
    @Test func exclusiveWindowsFileSharingProducesUnavailableDatabase() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "benchgauge-sharing-\(UUID().uuidString).db")
        try Data("SQLite format 3\0".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let path = PlatformPaths.fileSystemPath(file)
        #expect(bg_file_status(path) == 1)
        let handle = try #require(bg_lock_file(path))
        #expect(CCSwitchProviderStore.loadCodexProviders(databaseURL: file) == .unavailable)
        bg_unlock_file(handle)
        #expect(CCSwitchProviderStore.loadCodexProviders(databaseURL: file) == .absent)
    }
    #endif
}
