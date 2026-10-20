import Foundation
#if os(Windows)
import CPlatformSupport
#else
import CryptoKit
#endif

/// BenchGauge owns a separate OAuth session for each selected CC Switch account.
/// Never migrate/copy CC Switch's rotating refresh token into this directory.
public enum XAILoginStore {
    public static var directory: URL {
        PlatformPaths.applicationSupport.appending(path: "xai", directoryHint: .isDirectory)
    }

    public static func selectedAccountID(sharedAuthURL: URL = CCSwitchProviderStore.defaultXAIAuthURL) -> String? {
        guard let data = try? Data(contentsOf: sharedAuthURL),
              let snapshot = XaiAuthFile.parse(data) else { return nil }
        return XaiAuthFile.selectedAccount(snapshot)?.id
    }

    public static func authURL(sharedAuthURL: URL = CCSwitchProviderStore.defaultXAIAuthURL,
                               directory: URL = directory) -> URL {
        return authURL(accountID: selectedAccountID(sharedAuthURL: sharedAuthURL), directory: directory)
    }

    static func authURL(accountID: String?, directory: URL = directory) -> URL {
        guard let id = accountID else {
            return directory.appending(path: "unselected.json")
        }
        let data = Data(id.utf8)
        #if os(Windows)
        var digest = [UInt8](repeating: 0, count: 32)
        let ok = data.withUnsafeBytes { bg_sha256($0.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), &digest) }
        precondition(ok != 0, "Windows SHA256 unavailable")
        let key = digest.map { String(format: "%02x", $0) }.joined()
        #else
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #endif
        return directory.appending(path: "account-\(key).json")
    }

    static func isAppManaged(_ url: URL, directory: URL = directory) -> Bool {
        // URL equality includes its directory hint, which differs before the
        // first login creates the directory. Compare normalized path components.
        url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.pathComponents
            == directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}
