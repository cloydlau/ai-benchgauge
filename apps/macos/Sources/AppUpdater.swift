import AppKit
import Combine
import Sparkle

/// Sparkle owns scheduling, signature verification, installation, and relaunch.
/// Rendering a view never starts it; only the application delegate does.
@MainActor
final class AppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    static let willPresentUpdate = Notification.Name("AI-BenchGauge.willPresentUpdate")
    @Published private(set) var canCheckForUpdates = false
    private var updater: SPUUpdater?
    private var observation: AnyCancellable?

    func start() {
        guard updater == nil, Bundle.main.bundleURL.pathExtension == "app",
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else { return }
        let driver = InstallAndRelaunchUserDriver(hostBundle: .main, delegate: self)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do {
            try updater.start()
            self.updater = updater
            observation = updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
        } catch {
            NSLog("AI BenchGauge updater could not start: %@", error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NotificationCenter.default.post(name: Self.willPresentUpdate, object: nil)
        updater?.checkForUpdates()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate {
            NotificationCenter.default.post(name: Self.willPresentUpdate, object: nil)
        }
    }

    func standardUserDriverWillShowModalAlert() {
        NotificationCenter.default.post(name: Self.willPresentUpdate, object: nil)
    }
}

/// The initial Install Update click authorizes downloading and restarting.
/// Keep Sparkle's progress/cancel UI, without requiring a second install click.
@MainActor
final class InstallAndRelaunchUserDriver: SPUStandardUserDriver {
    // Sparkle exposes this through its Objective-C protocol, not its class header.
    @objc(showReadyToInstallAndRelaunch:)
    func installReadyUpdate(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
}
