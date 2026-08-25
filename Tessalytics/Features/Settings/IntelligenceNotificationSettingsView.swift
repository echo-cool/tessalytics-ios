import SwiftUI

struct IntelligenceNotificationSettingsView: View {
    @AppStorage(IntelligenceNotificationKeys.enabled) private var enabled = false
    @AppStorage(IntelligenceNotificationKeys.lowBattery) private var lowBattery = true
    @AppStorage(IntelligenceNotificationKeys.chargeComplete) private var chargeComplete = true
    @AppStorage(IntelligenceNotificationKeys.anomalies) private var anomalies = true
    @AppStorage(IntelligenceNotificationKeys.softwareUpdates) private var softwareUpdates = true
    @AppStorage(IntelligenceNotificationKeys.lowBatteryThreshold) private var lowBatteryThreshold = 20
    @State private var authorization: IntelligenceNotificationAuthorization = .notDetermined
    @State private var permissionRequestID = 0
    @State private var testRequestID = 0
    @State private var message: String?

    var body: some View {
        TessalyticsScreen {
            Form {
                Section {
                    Toggle("Intelligence notifications", isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            if newValue { permissionRequestID += 1 }
                        }
                    LabeledContent("Permission", value: authorizationLabel)
                } header: {
                    Label("Notifications", systemImage: "bell.badge.fill")
                } footer: {
                    Text("Alerts are created on this device.")
                }

                Section("Vehicle alerts") {
                    Toggle("Low battery", isOn: $lowBattery)
                    Stepper("Low battery threshold: \(lowBatteryThreshold)%", value: $lowBatteryThreshold, in: 10...40, step: 5)
                        .disabled(!lowBattery)
                    Toggle("Predicted charging completion", isOn: $chargeComplete)
                    Toggle("Software updates", isOn: $softwareUpdates)
                }
                .disabled(!enabled)

                Section {
                    Toggle("Important anomalies", isOn: $anomalies)
                } header: {
                    Text("Analytics alerts")
                } footer: {
                    Text("Forecasts stay available in the app even with alerts off.")
                }
                .disabled(!enabled)

                Section {
                    Button("Send test notification", systemImage: "bell.and.waves.left.and.right.fill") {
                        testRequestID += 1
                    }
                    .disabled(!enabled || authorization != .authorized)
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message.contains("Unable") ? TessalyticsTheme.critical : .secondary)
                    }
                } footer: {
                    Text("Checked on each refresh. A charging-completion alert is then scheduled to fire after the app closes.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .task { authorization = await IntelligenceNotificationService.shared.authorization() }
        .task(id: permissionRequestID) {
            guard permissionRequestID > 0, enabled else { return }
            await requestPermission()
        }
        .task(id: testRequestID) {
            guard testRequestID > 0 else { return }
            await sendTest()
        }
        .accessibilityIdentifier("intelligence-notification-settings")
    }

    private var authorizationLabel: String {
        switch authorization {
        case .authorized: "Allowed"
        case .denied: "Blocked in system settings"
        case .notDetermined: "Not requested"
        }
    }

    @MainActor
    private func requestPermission() async {
        do {
            let granted = try await IntelligenceNotificationService.shared.requestAuthorization()
            authorization = granted ? .authorized : .denied
            if !granted {
                enabled = false
                message = "Notifications were not allowed. You can enable them later in system Settings."
            } else {
                message = "Notifications are enabled."
            }
        } catch {
            enabled = false
            authorization = await IntelligenceNotificationService.shared.authorization()
            message = "Unable to enable notifications: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendTest() async {
        do {
            try await IntelligenceNotificationService.shared.sendTestNotification()
            message = "Test notification scheduled."
        } catch {
            message = "Unable to schedule a test notification: \(error.localizedDescription)"
        }
    }
}
