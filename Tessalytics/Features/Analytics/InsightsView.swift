import SwiftUI

private enum AnalysisSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case driving = "Drive"
    case charging = "Charge"
    case efficiency = "Efficiency"
    case mileage = "Mileage"
    case forecast = "Forecast"
    case battery = "Battery"

    var id: Self { self }

    var helpTitle: String {
        switch self {
        case .overview, .driving, .charging, .efficiency, .mileage: "Dashboard help"
        case .forecast: "Forecast help"
        case .battery: "Battery help"
        }
    }

    var helpText: String {
        switch self {
        case .overview, .driving, .charging, .mileage:
            "Charts cover synchronized drives and charges for the selected period. Drag across a chart to inspect a day."
        case .efficiency:
            "Consumption is weighted by distance, so a short cold trip does not count the same as a long one."
        case .forecast:
            "Forecasts use recent history. The shaded range shows expected variation."
        case .battery:
            "Battery values are estimates from charging and range data. Temperature and calibration affect them."
        }
    }
}

struct InsightsView: View {
    @State private var section = AnalysisSection.overview
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AnalysisModeBar(selection: $section)

                switch section {
                case .overview:
                    AnalyticsDashboardView(embedded: true, initialSection: .overview, showsSectionControl: false)
                case .driving:
                    AnalyticsDashboardView(embedded: true, initialSection: .driving, showsSectionControl: false)
                case .charging:
                    AnalyticsDashboardView(embedded: true, initialSection: .charging, showsSectionControl: false)
                case .efficiency:
                    AnalyticsDashboardView(embedded: true, initialSection: .efficiency, showsSectionControl: false)
                case .mileage:
                    AnalyticsDashboardView(embedded: true, initialSection: .mileage, showsSectionControl: false)
                case .forecast:
                    IntelligenceView(embedded: true)
                case .battery:
                    BatteryHealthView(embedded: true)
                }
            }
            .background { TessalyticsBackdrop() }
            .navigationTitle("Analysis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Help", systemImage: "questionmark.circle") { showingHelp = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showingHelp) {
                AnalysisHelpSheet(section: section)
                    .presentationDetents([.medium])
            }
        }
        .accessibilityIdentifier("insights-screen")
    }
}

private struct AnalysisModeBar: View {
    @Binding var selection: AnalysisSection

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(AnalysisSection.allCases) { section in
                    // Padding and background belong inside the label: applied to
                    // the Button they sit outside its hit region, leaving only
                    // the text itself tappable.
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == section ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                selection == section ? TessalyticsTheme.accent : Color.secondary.opacity(0.12),
                                in: .capsule
                            )
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analysis mode")
    }
}

private struct AnalysisHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let section: AnalysisSection

    var body: some View {
        NavigationStack {
            TessalyticsScreen {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(TessalyticsTheme.accent)
                        .accessibilityHidden(true)
                    Text(section.helpText)
                        .font(.body)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(section.helpTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { TessalyticsDismissButton() }
            }
        }
    }
}
