import Charts
import SwiftData
import SwiftUI

struct AnalyticsDashboardView: View {
    var embedded: Bool
    var showsSectionControl: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var section: AnalyticsSection
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var customStart = Date.now.addingTimeInterval(-30 * 86_400)
    @State private var customEnd = Date.now
    @State private var driveSamples: [AnalyticsDriveSample] = []
    @State private var chargeSamples: [AnalyticsChargeSample] = []
    @State private var dashboard: AnalyticsDashboardSnapshot?
    @State private var distanceUnit = ""

    init(
        embedded: Bool = false,
        initialSection: AnalyticsSection = .overview,
        showsSectionControl: Bool = true
    ) {
        self.embedded = embedded
        self.showsSectionControl = showsSectionControl
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        TessalyticsScreen(showsTopAccent: !embedded) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !embedded {
                        AnalyticsHero(snapshot: dashboard, windowLabel: window.label)
                    }
                    AnalyticsControls(
                        section: $section,
                        period: $period,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        showsSectionControl: showsSectionControl
                    )

                    if let dashboard {
                        switch section {
                        case .overview:
                            AnalyticsOverviewDashboard(
                                snapshot: dashboard,
                                periodLabel: window.label,
                                comparisonLabel: window.comparisonLabel,
                                distanceUnit: distanceUnit
                            )
                        case .driving:
                            DrivingAnalyticsDashboard(
                                snapshot: dashboard,
                                periodLabel: window.label,
                                comparisonLabel: window.comparisonLabel,
                                distanceUnit: distanceUnit
                            )
                        case .charging:
                            ChargingAnalyticsDashboard(
                                snapshot: dashboard,
                                periodLabel: window.label,
                                comparisonLabel: window.comparisonLabel
                            )
                        }
                    } else {
                        LoadingPanel(title: "Building analytics dashboard", symbol: "chart.xyaxis.line")
                    }

                    if !embedded {
                        AnalyticsSourceNote(coverage: dashboard?.coverage)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(embedded ? "Analysis" : "Analytics")
        .task(id: environment.selectedVehicle?.id) { load() }
        .onChange(of: period) { rebuildDashboard() }
        .onChange(of: customStart) { rebuildDashboard() }
        .onChange(of: customEnd) { rebuildDashboard() }
        .accessibilityIdentifier("analytics-dashboard-screen")
    }

    private var window: AnalyticsTimeWindow {
        AnalyticsTimeWindow.resolve(period: period, customStart: customStart, customEnd: customEnd)
    }

    private func load() {
        if environment.isDemoMode {
            let samples = DemoAnalyticsFactory.samples()
            driveSamples = samples.drives
            chargeSamples = samples.charges
            distanceUnit = "km"
            rebuildDashboard()
            return
        }

        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            driveSamples = []
            chargeSamples = []
            rebuildDashboard()
            return
        }

        driveSamples = DriveRepository(context: context)
            .cached(serverID: profile.id, carID: vehicle.id)
            .compactMap { record in
                guard let date = record.startDate else { return nil }
                return AnalyticsDriveSample(
                    id: record.driveID,
                    date: date,
                    distance: record.distance,
                    durationMinutes: record.durationMinutes,
                    energy: record.energy,
                    efficiency: record.efficiency,
                    destination: record.endAddress
                )
            }
        chargeSamples = ChargeRepository(context: context)
            .cached(serverID: profile.id, carID: vehicle.id)
            .compactMap { record in
                guard let date = record.startDate else { return nil }
                return AnalyticsChargeSample(
                    id: record.chargeID,
                    date: date,
                    energy: record.energyAdded,
                    cost: record.cost,
                    durationMinutes: record.durationMinutes,
                    location: record.address
                )
            }

        let serverID = profile.id.uuidString
        let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == serverID })
        distanceUnit = (try? context.fetch(descriptor).first?.lengthUnit) ?? ""
        rebuildDashboard()
    }

    private func rebuildDashboard() {
        dashboard = AnalyticsDashboardBuilder().make(drives: driveSamples, charges: chargeSamples, window: window)
    }
}

enum AnalyticsSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case driving = "Driving"
    case charging = "Charging"
    var id: Self { self }
}

private struct AnalyticsHero: View {
    let snapshot: AnalyticsDashboardSnapshot?
    let windowLabel: String

    private var title: String {
        guard let snapshot, snapshot.coverage.drives + snapshot.coverage.charges > 0 else { return "Your mobility, clearly explained" }
        return "\(snapshot.coverage.drives) drives · \(snapshot.coverage.charges) charges"
    }

    var body: some View {
        DashboardHeroCard(
            eyebrow: "Analytics hub",
            title: title,
            subtitle: "Explore movement, efficiency, charging cost, and data quality from synchronized TeslaMate history.",
            symbol: "chart.xyaxis.line",
            badge: windowLabel
        )
    }
}

private struct AnalyticsControls: View {
    @Binding var section: AnalyticsSection
    @Binding var period: AnalyticsPeriod
    @Binding var customStart: Date
    @Binding var customEnd: Date
    let showsSectionControl: Bool

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                if showsSectionControl {
                    Picker("Dashboard", selection: $section) {
                        ForEach(AnalyticsSection.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Label("Reporting period", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 12)
                    Picker("Reporting period", selection: $period) {
                        ForEach(AnalyticsPeriod.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if period == .custom {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { datePickers }
                        VStack(spacing: 12) { datePickers }
                    }
                }
            }
        }
    }

    @ViewBuilder private var datePickers: some View {
        DatePicker("From", selection: $customStart, displayedComponents: .date)
        DatePicker("Through", selection: $customEnd, displayedComponents: .date)
    }
}

private struct AnalyticsOverviewDashboard: View {
    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?
    let distanceUnit: String

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                MetricCard(
                    title: "Distance",
                    value: ValueFormatting.number(snapshot.summary.distance, unit: distanceUnit),
                    symbol: "road.lanes",
                    detail: comparison(snapshot.summary.distance, snapshot.previousSummary?.distance, label: comparisonLabel)
                )
                MetricCard(
                    title: "Driving time",
                    value: ValueFormatting.duration(minutes: snapshot.summary.drivingMinutes),
                    symbol: "clock.fill",
                    detail: comparison(Double(snapshot.summary.drivingMinutes), snapshot.previousSummary.map { Double($0.drivingMinutes) }, label: comparisonLabel),
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Charging energy",
                    value: ValueFormatting.number(snapshot.summary.chargingEnergy, unit: "kWh"),
                    symbol: "bolt.fill",
                    detail: comparison(snapshot.summary.chargingEnergy, snapshot.previousSummary?.chargingEnergy, label: comparisonLabel),
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Charging cost",
                    value: ValueFormatting.currency(snapshot.summary.chargingCost),
                    symbol: "creditcard.fill",
                    detail: comparison(snapshot.summary.chargingCost, snapshot.previousSummary?.chargingCost, label: comparisonLabel),
                    tint: TessalyticsTheme.steel
                )
            }

            DailyDistanceChart(points: snapshot.dailyDriving, periodLabel: periodLabel, distanceUnit: distanceUnit)
            WeekdayActivityChart(points: snapshot.weekdayActivity, distanceUnit: distanceUnit)
            TimeOfDayMixChart(points: snapshot.timeOfDayMix)
            AnalyticsCoverageCard(coverage: snapshot.coverage)
        }
    }
}

private struct DrivingAnalyticsDashboard: View {
    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?
    let distanceUnit: String

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                MetricCard(
                    title: "Trips",
                    value: snapshot.summary.driveCount.formatted(),
                    symbol: "car.side.fill",
                    detail: comparison(Double(snapshot.summary.driveCount), snapshot.previousSummary.map { Double($0.driveCount) }, label: comparisonLabel)
                )
                MetricCard(
                    title: "Average trip",
                    value: ValueFormatting.number(snapshot.summary.averageTripDistance, unit: distanceUnit),
                    symbol: "arrow.left.and.right",
                    detail: comparison(snapshot.summary.averageTripDistance, snapshot.previousSummary?.averageTripDistance, label: comparisonLabel),
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Reported efficiency",
                    value: ValueFormatting.number(snapshot.summary.averageEfficiency, unit: efficiencyUnit),
                    symbol: "gauge.with.dots.needle.67percent",
                    detail: comparison(snapshot.summary.averageEfficiency, snapshot.previousSummary?.averageEfficiency, label: comparisonLabel),
                    tint: TessalyticsTheme.warning
                )
                MetricCard(title: "Driving time", value: ValueFormatting.duration(minutes: snapshot.summary.drivingMinutes), symbol: "timer", tint: TessalyticsTheme.steel)
            }

            DailyDistanceChart(points: snapshot.dailyDriving, periodLabel: periodLabel, distanceUnit: distanceUnit)
            EfficiencyTrendChart(points: snapshot.efficiencyTrend, unit: efficiencyUnit)
            WeekdayActivityChart(points: snapshot.weekdayActivity, distanceUnit: distanceUnit)
            TimeOfDayMixChart(points: snapshot.timeOfDayMix)
            RankedCategoryChart(
                title: "Common destinations",
                subtitle: "Top destinations by completed trip count",
                symbol: "flag.checkered",
                tint: TessalyticsTheme.accent,
                points: snapshot.destinations,
                valueLabel: "Trips",
                unit: "trips"
            )
        }
    }

    private var efficiencyUnit: String { distanceUnit.isEmpty ? "reported" : "Wh/\(distanceUnit)" }
}

private struct ChargingAnalyticsDashboard: View {
    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                MetricCard(
                    title: "Energy added",
                    value: ValueFormatting.number(snapshot.summary.chargingEnergy, unit: "kWh"),
                    symbol: "bolt.fill",
                    detail: comparison(snapshot.summary.chargingEnergy, snapshot.previousSummary?.chargingEnergy, label: comparisonLabel),
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Total cost",
                    value: ValueFormatting.currency(snapshot.summary.chargingCost),
                    symbol: "creditcard.fill",
                    detail: comparison(snapshot.summary.chargingCost, snapshot.previousSummary?.chargingCost, label: comparisonLabel),
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Average price",
                    value: snapshot.summary.averagePricePerKWh.map { ValueFormatting.currency($0) + "/kWh" } ?? "Unavailable",
                    symbol: "dollarsign.arrow.circlepath",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(title: "Sessions", value: snapshot.coverage.charges.formatted(), symbol: "bolt.car.fill", tint: TessalyticsTheme.steel)
            }

            ChargingEnergyChart(points: snapshot.dailyCharging, periodLabel: periodLabel)
            ChargingCostChart(points: snapshot.dailyCharging, periodLabel: periodLabel)
            ChargeCostRelationshipChart(points: snapshot.chargeRelationships)
            RankedCategoryChart(
                title: "Charging by location",
                subtitle: "Energy added by the six most-used reported locations",
                symbol: "mappin.and.ellipse",
                tint: TessalyticsTheme.positive,
                points: snapshot.chargingLocations,
                valueLabel: "Energy",
                unit: "kWh"
            )
            AnalyticsCoverageCard(coverage: snapshot.coverage)
        }
    }
}

private struct DailyDistanceChart: View {
    let points: [AnalyticsDailyDrivePoint]
    let periodLabel: String
    let distanceUnit: String
    @State private var selectedDate: Date?

    private var selectedPoint: AnalyticsDailyDrivePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        SectionCard("Distance by day", subtitle: "Completed-drive distance · \(periodLabel)", symbol: "chart.bar.fill") {
            if points.isEmpty {
                ChartEmptyState(message: "No distance observations in this period.")
            } else {
                ChartSelectionReadout(
                    title: selectedPoint?.date.formatted(date: .abbreviated, time: .omitted) ?? "Select a day",
                    value: selectedPoint.map { ValueFormatting.number($0.distance, unit: distanceUnit) },
                    detail: selectedPoint.map { "\($0.trips) trip\($0.trips == 1 ? "" : "s")" }
                )
                Chart(points) { point in
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Distance", point.distance))
                        .foregroundStyle(TessalyticsTheme.accent)
                        .clipShape(.rect(cornerRadius: 4))
                    if let selectedDate {
                        RuleMark(x: .value("Selected date", selectedDate))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartYScale(domain: 0...max(1, (points.map(\.distance).max() ?? 1) * 1.12))
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Daily driving distance")
                .accessibilityIdentifier("daily-distance-chart")
                .sensoryFeedback(.selection, trigger: selectedDate)
            }
        }
    }
}

private struct ChargingEnergyChart: View {
    let points: [AnalyticsDailyChargePoint]
    let periodLabel: String
    @State private var selectedDate: Date?

    private var selectedPoint: AnalyticsDailyChargePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        SectionCard("Charging energy", subtitle: "Energy added per charging day · \(periodLabel)", symbol: "bolt.fill", tint: TessalyticsTheme.positive) {
            if points.isEmpty {
                ChartEmptyState(message: "No charging-energy observations in this period.")
            } else {
                ChartSelectionReadout(
                    title: selectedPoint?.date.formatted(date: .abbreviated, time: .omitted) ?? "Select a charging day",
                    value: selectedPoint.map { ValueFormatting.number($0.energy, unit: "kWh") },
                    detail: selectedPoint.map { "\($0.sessions) session\($0.sessions == 1 ? "" : "s")" }
                )
                Chart(points) { point in
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Energy added", point.energy))
                        .foregroundStyle(TessalyticsTheme.positive)
                        .clipShape(.rect(cornerRadius: 4))
                    if let selectedDate {
                        RuleMark(x: .value("Selected date", selectedDate))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartYScale(domain: 0...max(1, (points.map(\.energy).max() ?? 1) * 1.12))
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Charging energy by day in kilowatt-hours")
                .sensoryFeedback(.selection, trigger: selectedDate)
            }
        }
    }
}

private struct ChargingCostChart: View {
    let points: [AnalyticsDailyChargePoint]
    let periodLabel: String

    var body: some View {
        SectionCard("Charging cost trend", subtitle: "Reported charging cost per charging day · \(periodLabel)", symbol: "chart.xyaxis.line", tint: TessalyticsTheme.neutral) {
            if points.count < 8 {
                ChartEmptyState(message: "At least eight charging days are needed for a meaningful cost trend. \(points.count) available.")
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Charging cost", point.cost))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.neutral)
                    PointMark(x: .value("Date", point.date), y: .value("Charging cost", point.cost))
                        .foregroundStyle(TessalyticsTheme.neutral)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartYScale(domain: 0...max(1, (points.map(\.cost).max() ?? 1) * 1.12))
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Charging cost trend over \(points.count) charging days")
            }
        }
    }
}

private struct EfficiencyTrendChart: View {
    let points: [AnalyticsEfficiencyPoint]
    let unit: String

    var body: some View {
        SectionCard("Efficiency trend", subtitle: "Reported consumption per completed drive · \(points.count) observations", symbol: "leaf.fill", tint: TessalyticsTheme.warning) {
            if points.count < 8 {
                ChartEmptyState(message: "At least eight drives with efficiency data are needed for a meaningful trend. \(points.count) available.")
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Reported efficiency", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.warning)
                    PointMark(x: .value("Date", point.date), y: .value("Reported efficiency", point.value))
                        .foregroundStyle(TessalyticsTheme.warning)
                        .symbolSize(28)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Reported drive efficiency trend in \(unit)")
            }
        }
    }
}

private struct WeekdayActivityChart: View {
    let points: [AnalyticsCategoryPoint]
    let distanceUnit: String

    var body: some View {
        SectionCard("Activity by weekday", subtitle: "Total distance grouped by local calendar weekday", symbol: "calendar.badge.clock", tint: TessalyticsTheme.neutral) {
            if points.allSatisfy({ $0.value == 0 }) {
                ChartEmptyState(message: "No weekday distance data in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Weekday", point.label), y: .value("Distance", point.value))
                        .foregroundStyle(TessalyticsTheme.neutral)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartYScale(domain: 0...max(1, (points.map(\.value).max() ?? 1) * 1.12))
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Distance by weekday in \(distanceUnit.isEmpty ? "server distance units" : distanceUnit)")
            }
        }
    }
}

private struct TimeOfDayMixChart: View {
    let points: [AnalyticsCategoryPoint]

    private let colors: [String: Color] = [
        "Morning": TessalyticsTheme.warning,
        "Afternoon": TessalyticsTheme.accent,
        "Evening": TessalyticsTheme.neutral,
        "Night": TessalyticsTheme.steel
    ]

    var body: some View {
        SectionCard("Trip timing", subtitle: "Completed trips by local start time", symbol: "clock.badge") {
            if points.allSatisfy({ $0.count == 0 }) {
                ChartEmptyState(message: "No trip start times in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Trips", point.count), y: .value("All trips", "Trips"))
                        .foregroundStyle(by: .value("Time of day", point.label))
                }
                .chartForegroundStyleScale([
                    "Morning": TessalyticsTheme.warning,
                    "Afternoon": TessalyticsTheme.accent,
                    "Evening": TessalyticsTheme.neutral,
                    "Night": TessalyticsTheme.steel
                ])
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading)
                .tessalyticsChartStyle()
                .frame(height: 92)
                .accessibilityLabel("Trip count composition by time of day")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(points) { point in
                        CompactStat(title: point.label, value: point.count.formatted(), tint: colors[point.label] ?? TessalyticsTheme.accent)
                    }
                }
            }
        }
    }
}

private struct ChargeCostRelationshipChart: View {
    let points: [AnalyticsChargeRelationshipPoint]

    var body: some View {
        SectionCard("Energy and cost", subtitle: "Session-level relationship · one point per charge with energy and cost", symbol: "circle.hexagongrid.fill", tint: TessalyticsTheme.neutral) {
            if points.count < 12 {
                ChartEmptyState(message: "At least 12 complete charging sessions are needed to reveal a reliable relationship. \(points.count) available.")
            } else {
                Chart(points) { point in
                    PointMark(x: .value("Energy added", point.energy), y: .value("Charging cost", point.cost))
                        .foregroundStyle(by: .value("Location", point.location))
                        .symbol(by: .value("Location", point.location))
                        .symbolSize(54)
                }
                .chartXScale(domain: 0...max(1, (points.map(\.energy).max() ?? 1) * 1.1))
                .chartYScale(domain: 0...max(1, (points.map(\.cost).max() ?? 1) * 1.1))
                .chartXAxisLabel("Energy added (kWh)")
                .chartYAxisLabel("Cost")
                .chartForegroundStyleScale(range: [
                    TessalyticsTheme.accent,
                    TessalyticsTheme.neutral,
                    TessalyticsTheme.steel,
                    TessalyticsTheme.positive,
                    TessalyticsTheme.warning
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .tessalyticsChartStyle()
                .frame(height: 270)
                .accessibilityLabel("Charging energy and cost relationship across \(points.count) sessions")
            }
        }
    }
}

private struct RankedCategoryChart: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let points: [AnalyticsCategoryPoint]
    let valueLabel: String
    let unit: String

    var body: some View {
        SectionCard(title, subtitle: subtitle, symbol: symbol, tint: tint) {
            if points.isEmpty {
                ChartEmptyState(message: "No reported location data in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value(valueLabel, point.value), y: .value("Location", point.label))
                        .foregroundStyle(tint)
                        .clipShape(.rect(cornerRadius: 4))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(point.value.formatted(.number.precision(.fractionLength(0...1))))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXScale(domain: 0...max(1, (points.map(\.value).max() ?? 1) * 1.2))
                .chartXAxis { AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
                .tessalyticsChartStyle()
                .frame(height: max(170, CGFloat(points.count) * 42))
                .accessibilityLabel("\(title), values in \(unit)")
            }
        }
    }
}

private struct AnalyticsCoverageCard: View {
    let coverage: AnalyticsCoverage

    var body: some View {
        SectionCard("Data coverage", subtitle: "Completeness of synchronized fields used in this dashboard", symbol: "checkmark.seal.fill", tint: TessalyticsTheme.neutral) {
            VStack(spacing: 14) {
                CoverageRow(title: "Drive distance", available: coverage.drivesWithDistance, total: coverage.drives, tint: TessalyticsTheme.accent)
                CoverageRow(title: "Drive efficiency", available: coverage.drivesWithEfficiency, total: coverage.drives, tint: TessalyticsTheme.warning)
                CoverageRow(title: "Charge energy", available: coverage.chargesWithEnergy, total: coverage.charges, tint: TessalyticsTheme.positive)
                CoverageRow(title: "Charge cost", available: coverage.chargesWithCost, total: coverage.charges, tint: TessalyticsTheme.neutral)
            }
        }
    }
}

private struct CoverageRow: View {
    let title: String
    let available: Int
    let total: Int
    let tint: Color

    private var fraction: Double { total == 0 ? 0 : Double(available) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                Text("\(available) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(available) of \(total) observations")
    }
}

private struct ChartSelectionReadout: View {
    let title: String
    let value: String?
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .accessibilityElement(children: .combine)
    }
}

private struct ChartEmptyState: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "chart.xyaxis.line")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}

private struct AnalyticsSourceNote: View {
    let coverage: AnalyticsCoverage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("TeslaMate source data", systemImage: "externaldrive.connected.to.line.below")
                .font(.caption.weight(.semibold))
            Text("Totals use synchronized records for the selected vehicle and period. Missing distance, energy, efficiency, or cost values are excluded rather than treated as zero. Calculated averages are estimates.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let date = coverage?.latestActivity {
                Text("Latest included activity: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

private func comparison(_ current: Double?, _ previous: Double?, label: String?) -> String? {
    guard let current, let previous, previous != 0, let label else { return nil }
    let percent = (current - previous) / abs(previous) * 100
    let prefix = percent > 0 ? "+" : ""
    return "\(prefix)\(percent.formatted(.number.precision(.fractionLength(0))))% vs \(label)"
}
