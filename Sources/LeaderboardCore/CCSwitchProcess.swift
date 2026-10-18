import Foundation
#if os(macOS)
import AppKit
#elseif os(Windows)
import CPlatformSupport
#endif

/// CC Switch caches the shared refresh token until it exits. Process detection
/// is a conservative guard, not a lock that CC Switch participates in.
enum CCSwitchProcess {
    static func isRunning() -> Bool {
        #if os(macOS)
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == CCSwitchProviderStore.bundleID ||
            $0.executableURL?.lastPathComponent == "cc-switch"
        }
        #elseif os(Windows)
        return bg_ccswitch_running() != 0
        #elseif os(Linux)
        // An unreadable process table must never permit shared-token rotation.
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return true }
        for entry in entries where Int(entry) != nil {
            let path = "/proc/\(entry)/comm"
            guard let name = try? String(contentsOfFile: path, encoding: .utf8) else {
                if FileManager.default.fileExists(atPath: path) { return true }
                continue // The process may have exited since enumeration.
            }
            if name.trimmingCharacters(in: .whitespacesAndNewlines) == "cc-switch" { return true }
        }
        return false
        #else
        return true
        #endif
    }
}
