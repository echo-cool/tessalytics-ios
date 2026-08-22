import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch environment.phase {
            case .loading:
                ProgressView("Opening Tessalytics…")
            case .onboarding:
                OnboardingView()
            case .ready:
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-drive-detail") {
                    NavigationStack { DriveDetailView(driveID: 1) }
                } else if ProcessInfo.processInfo.arguments.contains("-ui-drives") {
                    DriveHistoryView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-charges") {
                    ChargeHistoryView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-insights") {
                    InsightsView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-analytics") {
                    NavigationStack { AnalyticsDashboardView() }
                } else if ProcessInfo.processInfo.arguments.contains("-ui-battery") {
                    NavigationStack { BatteryHealthView() }
                } else if ProcessInfo.processInfo.arguments.contains("-ui-intelligence") {
                    NavigationStack { IntelligenceView() }
                } else {
                    MainTabView()
                }
                #else
                MainTabView()
                #endif
            }
        }
        .tint(TessalyticsTheme.accent)
        // Once, at launch. Game Center may answer "signed out", which is fine:
        // the achievements are computed on the device either way.
        .task { environment.gameCenter.authenticate() }
    }
}
