import AppKit
import Foundation
import LeaderboardCore
@preconcurrency import UserNotifications

/// Posts current-provider quota alerts and remembers which reset cycles
/// already produced a banner. A denied permission stays silent.
@MainActor
final class QuotaNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let deliveredDefaultsKey = "quotaAlertDeliveredKeys"

    private let defaults: UserDefaults
    private var delivered: Set<String>
    private var inFlight: Set<String> = []
    private var authorizationTask: Task<Bool, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        delivered = Set(defaults.stringArray(forKey: Self.deliveredDefaultsKey) ?? [])
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func consider(chips: [AccountQuotaChip], now: Date = Date()) {
        let alerts = chips.flatMap { QuotaAlerts.alerts(for: $0, now: now) }
        let active = Set(alerts.flatMap(\.componentKeys))
        let retained = QuotaAlerts.retainedKeys(
            delivered,
            evaluatedChips: chips,
            activeKeys: active
        )
        if retained != delivered {
            delivered = retained
            persist()
        }
        let pending = QuotaAlerts.pendingAlerts(alerts, delivered: delivered, inFlight: inFlight)
        guard !pending.isEmpty else { return }
        let keys = Set(pending.flatMap(\.componentKeys))
        inFlight.formUnion(keys)
        Task {
            let granted = await self.authorizationGranted()
            guard granted else {
                self.inFlight.subtract(keys)
                return
            }
            var sent: Set<String> = []
            for alert in pending {
                if await self.post(alert) {
                    sent.formUnion(alert.componentKeys)
                }
            }
            self.inFlight.subtract(keys)
            guard !sent.isEmpty else { return }
            self.delivered.formUnion(sent)
            self.persist()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    private func authorizationGranted() async -> Bool {
        if let authorizationTask {
            return await authorizationTask.value
        }
        let task = Task { @MainActor () -> Bool in
            await self.fetchAuthorization()
        }
        authorizationTask = task
        let granted = await task.value
        authorizationTask = nil
        return granted
    }

    private func fetchAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .enabled
        case .denied:
            return false
        case .notDetermined:
            NSApp.activate()
            do {
                return try await center.requestAuthorization(options: [.alert])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private func post(_ alert: QuotaAlert) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = alert.subtitle
        content.body = alert.body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    private func persist() {
        defaults.set(Array(delivered).sorted(), forKey: Self.deliveredDefaultsKey)
    }
}
