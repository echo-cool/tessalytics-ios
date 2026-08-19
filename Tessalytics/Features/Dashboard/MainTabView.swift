import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Status", systemImage: "gauge.with.dots.needle.67percent") { DashboardView() }
            Tab("Activity", systemImage: "clock.arrow.circlepath") { ActivityView() }
            Tab("Analysis", systemImage: "chart.xyaxis.line") { InsightsView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .tint(TessalyticsTheme.accent)
    }
}

private enum ActivitySection: String, CaseIterable, Identifiable {
    case drives = "Drives"
    case charging = "Charging"

    var id: Self { self }
}

struct ActivityView: View {
    @State private var section = ActivitySection.drives

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Activity", selection: $section) {
                    ForEach(ActivitySection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch section {
                case .drives:
                    DriveHistoryView(embedded: true)
                case .charging:
                    ChargeHistoryView(embedded: true)
                }
            }
            .background { TessalyticsBackdrop() }
            .navigationTitle("Activity")
        }
        .accessibilityIdentifier("activity-screen")
    }
}
