import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            #if DEBUG
            // The first-run screen exists only between adding a server and its
            // history arriving — a window neither a test nor a screenshot run
            // can otherwise stand in. Checked before the phase, because that
            // window is milliseconds wide when there is no server to talk to.
            if ProcessInfo.processInfo.arguments.contains("-ui-preparing") {
                PreparingView(
                    progress: .init(step: .history, drives: 412, charges: 96, isCountingHistory: true),
                    serverName: "Garage"
                )
            } else {
                phaseContent
            }
            #else
            phaseContent
            #endif
        }
        .tint(TessalyticsTheme.accent)
        // Once, at launch. Game Center may answer "signed out", which is fine:
        // the achievements are computed on the device either way.
        .task { environment.gameCenter.authenticate() }
    }

    @ViewBuilder private var phaseContent: some View {
        Group {
            switch environment.phase {
            case .loading:
                ProgressView("Opening Tessalytics…")
            case .onboarding:
                OnboardingView()
            case .preparing:
                PreparingView(
                    progress: environment.preparation,
                    serverName: environment.selectedProfile?.name,
                    onSkip: { environment.finishPreparing() }
                )
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
    }
}
