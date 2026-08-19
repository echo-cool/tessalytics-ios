import Foundation
import UserNotifications

enum IntelligenceNotificationKeys {
    static let enabled = "intelligence.notifications.enabled"
    static let lowBattery = "intelligence.notifications.lowBattery"
    static let chargeComplete = "intelligence.notifications.chargeComplete"
    static let anomalies = "intelligence.notifications.anomalies"
    static let softwareUpdates = "intelligence.notifications.softwareUpdates"
    static let lowBatteryThreshold = "intelligence.notifications.lowBatteryThreshold"
}

struct IntelligenceNotificationPreferences: Sendable, Equatable {
    var enabled: Bool
    var lowBattery: Bool
    var chargeComplete: Bool
    var anomalies: Bool
    var softwareUpdates: Bool
    var lowBatteryThreshold: Int

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        func bool(_ key: String, fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        let savedThreshold = defaults.object(forKey: IntelligenceNotificationKeys.lowBatteryThreshold) as? Int
        return Self(
            enabled: bool(IntelligenceNotificationKeys.enabled, fallback: false),
            lowBattery: bool(IntelligenceNotificationKeys.lowBattery, fallback: true),
            chargeComplete: bool(IntelligenceNotificationKeys.chargeComplete, fallback: true),
            anomalies: bool(IntelligenceNotificationKeys.anomalies, fallback: true),
            softwareUpdates: bool(IntelligenceNotificationKeys.softwareUpdates, fallback: true),
            lowBatteryThreshold: min(max(savedThreshold ?? 20, 10), 40)
        )
    }
}

enum IntelligenceNotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

struct PlannedIntelligenceNotification: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let body: String
    let delay: TimeInterval?
    let fingerprint: String
}

struct IntelligenceNotificationPlanner {
    func statusNotifications(
        status: VehicleStatus,
        vehicleName: String,
        preferences: IntelligenceNotificationPreferences
    ) -> [PlannedIntelligenceNotification] {
        guard preferences.enabled else { return [] }
        var planned: [PlannedIntelligenceNotification] = []

        if preferences.lowBattery,
           let level = status.batteryDetails?.batteryLevel,
           level <= preferences.lowBatteryThreshold,
           status.chargingDetails?.pluggedIn != true {
            planned.append(
                PlannedIntelligenceNotification(
                    id: "tessalytics.low-battery",
                    title: "\(vehicleName) battery is low",
                    body: "The last reported level is \(level)%. Consider charging before your next drive.",
                    delay: nil,
                    fingerprint: "low-battery-\(level / 5)"
                )
            )
        }

        if preferences.chargeComplete,
           status.chargingDetails?.pluggedIn == true,
           status.chargingDetails?.chargingState?.localizedCaseInsensitiveContains("charging") == true,
           let hours = status.chargingDetails?.timeToFullCharge,
           hours > 0 {
            let target = status.chargingDetails?.chargeLimitSoc ?? 100
            planned.append(
                PlannedIntelligenceNotification(
                    id: "tessalytics.charge-complete",
                    title: "\(vehicleName) should be ready",
                    body: "Charging is predicted to reach the \(target)% target.",
                    delay: max(60, hours * 3_600),
                    fingerprint: "charge-complete-\(target)"
                )
            )
        }

        if preferences.softwareUpdates,
           status.carVersions?.updateAvailable == true {
            let version = status.carVersions?.updateVersion ?? "a new version"
            planned.append(
                PlannedIntelligenceNotification(
                    id: "tessalytics.software-update",
                    title: "Software update available",
                    body: "\(vehicleName) can update to \(version).",
                    delay: nil,
                    fingerprint: "software-\(version)"
                )
            )
        }
        return planned
    }

    func insightNotifications(
        insights: [VehicleInsight],
        vehicleName: String,
        preferences: IntelligenceNotificationPreferences
    ) -> [PlannedIntelligenceNotification] {
        guard preferences.enabled, preferences.anomalies else { return [] }
        return insights
            .filter { $0.severity == .warning || $0.severity == .critical }
            .map { insight in
                PlannedIntelligenceNotification(
                    id: "tessalytics.insight.\(insight.id)",
                    title: "\(vehicleName): \(insight.title)",
                    body: insight.message,
                    delay: nil,
                    fingerprint: "insight-\(insight.id)-\(insight.message)"
                )
            }
    }
}

actor IntelligenceNotificationService {
    static let shared = IntelligenceNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let planner = IntelligenceNotificationPlanner()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func authorization() async -> IntelligenceNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func updateStatusNotifications(
        status: VehicleStatus,
        vehicleName: String,
        preferences: IntelligenceNotificationPreferences
    ) async {
        let statusIDs = [
            "tessalytics.low-battery",
            "tessalytics.charge-complete",
            "tessalytics.software-update"
        ]
        center.removePendingNotificationRequests(withIdentifiers: statusIDs)
        guard preferences.enabled, await authorization() == .authorized else { return }
        let requests = planner.statusNotifications(status: status, vehicleName: vehicleName, preferences: preferences)
        for request in requests {
            await schedule(request, alwaysReplace: request.delay != nil)
        }
    }

    func publishInsightNotifications(
        insights: [VehicleInsight],
        vehicleName: String,
        preferences: IntelligenceNotificationPreferences
    ) async {
        guard preferences.enabled, await authorization() == .authorized else { return }
        let requests = planner.insightNotifications(insights: insights, vehicleName: vehicleName, preferences: preferences)
        for request in requests { await schedule(request, alwaysReplace: false) }
    }

    func sendTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tessalytics Intelligence is ready"
        content.body = "Predictions and vehicle alerts will appear here when enabled."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "tessalytics.test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try await center.add(request)
    }

    private func schedule(_ planned: PlannedIntelligenceNotification, alwaysReplace: Bool) async {
        let defaultsKey = "intelligence.notification.fingerprint.\(planned.id)"
        if !alwaysReplace, defaults.string(forKey: defaultsKey) == planned.fingerprint { return }

        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        let trigger = planned.delay.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        let request = UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            defaults.set(planned.fingerprint, forKey: defaultsKey)
        } catch {
            // Notification delivery is best-effort; the in-app insight remains available.
        }
    }
}
