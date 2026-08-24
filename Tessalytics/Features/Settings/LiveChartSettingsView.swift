import SwiftUI

/// Which charts the home screen draws while the car is driving.
///
/// Live charts are the one part of the app where taste genuinely differs: someone
/// watching consumption on a long trip and someone watching power out of a
/// junction want different screens, and neither wants to scroll past the other's.
/// So this is a choice rather than a default, including the choice of none.
struct LiveChartSettingsView: View {
    @AppStorage(LiveChartPreferences.metricsKey)
    private var storedMetrics = LiveChartPreferences.defaultEncodedMetrics
    @AppStorage(LiveChartPreferences.windowKey)
    private var storedWindowMinutes = LiveChartPreferences.defaultWindowMinutes

    private var preferences: LiveChartPreferences {
        LiveChartPreferences.decode(metrics: storedMetrics, windowMinutes: storedWindowMinutes)
    }

    var body: some View {
        List {
            Section {
                ForEach(LiveChartMetric.allCases) { metric in
                    Toggle(isOn: binding(for: metric)) {
                        Label(metric.title, systemImage: metric.symbol)
                    }
                    .accessibilityIdentifier("live-chart-toggle-\(metric.rawValue)")
                }
            } header: {
                Label("Charts while driving", systemImage: "chart.xyaxis.line")
            } footer: {
                Text("Drawn on the home screen under the vehicle card, in this order, for as long as the car is moving.")
            }

            Section {
                Picker("Window", selection: windowBinding) {
                    ForEach(LiveChartPreferences.windowChoices, id: \.self) { minutes in
                        Text(AppText.format("%@ min", "\(minutes)")).tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("live-chart-window")
            } header: {
                Label("How far back", systemImage: "clock.arrow.circlepath")
            } footer: {
                Text("Readings are kept in memory for fifteen minutes and are discarded when the drive ends.")
            }
        }
        .navigationTitle("Live charts")
        .accessibilityIdentifier("live-chart-settings")
    }

    private func binding(for metric: LiveChartMetric) -> Binding<Bool> {
        Binding(
            get: { preferences.contains(metric) },
            set: { storedMetrics = preferences.setting(metric, enabled: $0).encodedMetrics }
        )
    }

    private var windowBinding: Binding<Int> {
        Binding(get: { preferences.windowMinutes }, set: { storedWindowMinutes = $0 })
    }
}
