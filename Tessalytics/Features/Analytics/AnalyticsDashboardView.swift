import Charts
import SwiftData
import SwiftUI

struct AnalyticsDashboardView: View {
    var embedded: Bool
    var showsSectionControl: Bool
    @State private var chargingSites: [ChargingSite] = []

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var section: AnalyticsSection
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var customStart = Date.now.addingTimeInterval(-30 * 86_400)
    @State private var customEnd = Date.now
    @State private var driveSamples: [AnalyticsDriveSample] = []
    @State private var chargeSamples: [AnalyticsChargeSample] = []
    @State private var dashboard: AnalyticsDashboardSnapshot?
    @State private var distanceUnit = UnitsDTO.metricDefaults.lengthSymbol

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
                                comparisonLabel: window.comparisonLabel,
                                sites: chargingSites
                            )
                        }
                    } else {
                        LoadingPanel(title: "Building analytics dashboard", symbol: "chart.xyaxis.line")
                    }

                    if !embedded {
                        AnalyticsSourceNote(coverage: dashboard?.coverage)
                    }
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth()
            }
        }
        .navigationTitle(embedded ? "Analysis" : "Analytics")
        .shareablePage(sharePage) {
            VStack(spacing: 12) {
                if let dashboard {
                    // The controls are a segmented picker and a date range: a
                    // widget, not a fact, and meaningless in a still image. The
                    // window they select is named in the subtitle instead.
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
                            comparisonLabel: window.comparisonLabel,
                            sites: chargingSites
                        )
                    }
                    AnalyticsSourceNote(coverage: dashboard.coverage)
                }
            }
        }
        .task(id: environment.selectedVehicle?.id) { load() }
        .task(id: environment.historyRevision) { load() }
        .onChange(of: period) { rebuildDashboard() }
        .onChange(of: customStart) { rebuildDashboard() }
        .onChange(of: customEnd) { rebuildDashboard() }
        .accessibilityIdentifier("analytics-dashboard-screen")
    }


    private func sharePage() -> SharePage {
        let units = environment.statusUnits
        guard let summary = dashboard?.summary else {
            return SharePage(
                title: section.rawValue,
                subtitle: SharePage.subtitle(car: environment.selectedVehicle?.name)
            )
        }

        var highlights: [ShareHighlight] = [
            .init(label: "distance", value: ValueFormatting.distance(summary.distance, units: units, digits: 0)),
            .init(label: "drives", value: "\(summary.driveCount)")
        ]
        if summary.chargingEnergy != nil {
            highlights.append(.init(label: "charged", value: ValueFormatting.number(summary.chargingEnergy, unit: "kWh", digits: 0)))
        }
        if summary.averageEfficiency != nil {
            highlights.append(
                .init(label: "efficiency", value: ValueFormatting.efficiency(summary.averageEfficiency, units: units, digits: 0))
            )
        }

        var sentences = [
            "\(environment.selectedVehicle?.name?.nilIfEmpty ?? "My Tesla"), \(window.label.lowercased()): "
            + "\(ValueFormatting.distance(summary.distance, units: units, digits: 0)) over "
            + "\(summary.driveCount) drive\(summary.driveCount == 1 ? "" : "s")."
        ]
        if summary.chargingEnergy != nil {
            var line = "\(ValueFormatting.number(summary.chargingEnergy, unit: "kWh", digits: 0)) charged"
            if summary.chargingCost != nil {
                line += " for \(ValueFormatting.chargeCost(summary.chargingCost))"
            }
            sentences.append(line + ".")
        }
        sentences.append("Analysed by Tessalytics.")
        return SharePage(
            title: section.rawValue,
            // The window is what makes these figures mean anything, and a picture
            // of them without it is a picture of nothing in particular.
            subtitle: "\(environment.selectedVehicle?.name?.nilIfEmpty ?? "Tesla") · \(window.label)",
            highlights: highlights,
            summary: sentences.joined(separator: " ")
        )
    }

    private var window: AnalyticsTimeWindow {
        AnalyticsTimeWindow.resolve(period: period, customStart: customStart, customEnd: customEnd)
    }

    private func load() {
        if environment.isDemoMode {
            let samples = DemoAnalyticsFactory.samples()
            driveSamples = samples.drives
            chargeSamples = samples.charges
            distanceUnit = DemoExperience.units.lengthSymbol
            if let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle {
                chargingSites = ChargingSiteBuilder.sites(
                    from: ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
                )
            }
            rebuildDashboard()
            return
        }

        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            driveSamples = []
            chargeSamples = []
            chargingSites = []
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
        let chargeRecords = ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        chargeSamples = chargeRecords.compactMap { record in
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
        chargingSites = ChargingSiteBuilder.sites(from: chargeRecords)

        let serverID = profile.id.uuidString
        let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == serverID })
        distanceUnit = (try? context.fetch(descriptor).first?.lengthUnit)
            ?? environment.statusUnits?.lengthSymbol
            ?? UnitsDTO.metricDefaults.lengthSymbol
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
        return AppText.format("%1$@ drives · %2$@ charges", "\(snapshot.coverage.drives)", "\(snapshot.coverage.charges)")
    }

    var body: some View {
        DashboardHeroCard(
            eyebrow: "Analytics hub",
            title: title,
            subtitle: "Movement, efficiency, cost and data quality.",
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

    var body: some View {
        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
            MetricGrid {
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
                    value: ValueFormatting.chargeCost(snapshot.summary.chargingCost),
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

    var body: some View {
        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
            MetricGrid {
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
                MetricCard(
                    title: "Driving time",
                    value: ValueFormatting.duration(minutes: snapshot.summary.drivingMinutes),
                    symbol: "timer",
                    detail: averageTripDuration,
                    tint: TessalyticsTheme.steel
                )
            }

            DailyDistanceChart(points: snapshot.dailyDriving, periodLabel: periodLabel, distanceUnit: distanceUnit)
            EfficiencyTrendChart(points: snapshot.efficiencyTrend, unit: efficiencyUnit)
            WeekdayActivityChart(points: snapshot.weekdayActivity, distanceUnit: distanceUnit)
            TimeOfDayMixChart(points: snapshot.timeOfDayMix)
            RankedCategoryChart(
                title: "Common destinations",
                subtitle: "By completed trips",
                symbol: "flag.checkered",
                tint: TessalyticsTheme.accent,
                points: snapshot.destinations,
                valueLabel: "Trips",
                unit: "trips"
            )
        }
    }

    private var efficiencyUnit: String { distanceUnit.isEmpty ? "reported" : "Wh/\(distanceUnit)" }

    private var averageTripDuration: String {
        guard snapshot.summary.driveCount > 0 else { return "No trips recorded" }
        let minutes = snapshot.summary.drivingMinutes / snapshot.summary.driveCount
        return AppText.format("%@ per trip", ValueFormatting.duration(minutes: minutes))
    }
}

private struct ChargingAnalyticsDashboard: View {
    @Environment(\.isRenderingSharePoster) private var isRenderingPoster

    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?
    let sites: [ChargingSite]

    var body: some View {
        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
            MetricGrid {
                MetricCard(
                    title: "Energy added",
                    value: ValueFormatting.number(snapshot.summary.chargingEnergy, unit: "kWh"),
                    symbol: "bolt.fill",
                    detail: comparison(snapshot.summary.chargingEnergy, snapshot.previousSummary?.chargingEnergy, label: comparisonLabel),
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Total cost",
                    value: ValueFormatting.chargeCost(snapshot.summary.chargingCost),
                    symbol: "creditcard.fill",
                    detail: comparison(snapshot.summary.chargingCost, snapshot.previousSummary?.chargingCost, label: comparisonLabel),
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Average price",
                    value: snapshot.summary.averagePricePerKWh.map { ValueFormatting.currency($0) + "/kWh" } ?? "Unavailable",
                    symbol: "dollarsign.arrow.circlepath",
                    detail: snapshot.summary.averagePricePerKWh == nil
                        ? "No cost data reported"
                        : "Across priced sessions",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Sessions",
                    value: snapshot.coverage.charges.formatted(),
                    symbol: "bolt.car.fill",
                    detail: averageSessionEnergy,
                    tint: TessalyticsTheme.steel
                )
            }

            if !isRenderingPoster { ChargingMapCard(sites: sites) }
            ChargingEnergyChart(points: snapshot.dailyCharging, periodLabel: periodLabel)
            ChargingCostChart(points: snapshot.dailyCharging, periodLabel: periodLabel)
            ChargeCostRelationshipChart(points: snapshot.chargeRelationships)
            RankedCategoryChart(
                title: "Charging by location",
                subtitle: "Six most-used locations",
                symbol: "mappin.and.ellipse",
                tint: TessalyticsTheme.positive,
                points: snapshot.chargingLocations,
                valueLabel: "Energy",
                unit: "kWh"
            )
            AnalyticsCoverageCard(coverage: snapshot.coverage)
        }
    }

    private var averageSessionEnergy: String {
        guard snapshot.coverage.charges > 0, let energy = snapshot.summary.chargingEnergy else {
            return "No sessions in range"
        }
        let average = energy / Double(snapshot.coverage.charges)
        return "\(ValueFormatting.number(average, unit: "kWh")) average"
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
        SectionCard("Distance by day", subtitle: periodLabel, symbol: "chart.bar.fill") {
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...max(1, (points.map(\.distance).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Day", y: "Distance (\(distanceUnit))")
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Daily driving distance")
                .accessibilityIdentifier("daily-distance-chart")
                .sensoryFeedback(.selection, trigger: selectedDate)

                ChartLegend("Distance driven", color: TessalyticsTheme.accent)
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
        SectionCard("Charging energy", subtitle: periodLabel, symbol: "bolt.fill", tint: TessalyticsTheme.positive) {
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...max(1, (points.map(\.energy).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Day", y: "Energy (kWh)")
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Charging energy by day in kilowatt-hours")
                .sensoryFeedback(.selection, trigger: selectedDate)

                ChartLegend("Energy added", color: TessalyticsTheme.positive)
            }
        }
    }
}

private struct ChargingCostChart: View {
    let points: [AnalyticsDailyChargePoint]
    let periodLabel: String

    /// The axis has to name a currency; the device's is the best available guess
    /// because TeslaMate does not report one with the cost.
    static var currencyLabel: String { Locale.current.currency?.identifier ?? "cost" }

    var body: some View {
        SectionCard("Charging cost trend", subtitle: periodLabel, symbol: "chart.xyaxis.line", tint: TessalyticsTheme.neutral) {
            if points.count < 8 {
                ChartEmptyState(message: "At least eight charging days are needed for a meaningful cost trend. \(points.count) available.")
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Charging cost", point.cost))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.chartNeutral)
                    PointMark(x: .value("Date", point.date), y: .value("Charging cost", point.cost))
                        .foregroundStyle(TessalyticsTheme.chartNeutral)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...max(1, (points.map(\.cost).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Day", y: "Cost (\(Self.currencyLabel))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Charging cost trend over \(points.count) charging days")

                ChartLegend("Reported cost per charging day", color: TessalyticsTheme.chartNeutral)
            }
        }
    }
}

private struct EfficiencyTrendChart: View {
    let points: [AnalyticsEfficiencyPoint]
    let unit: String

    var body: some View {
        SectionCard("Efficiency trend", subtitle: AppText.format("%@ drives", "\(points.count)"), symbol: "leaf.fill", tint: TessalyticsTheme.warning) {
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .tessalyticsChartAxes(x: "Drive date", y: "Consumption (\(unit))")
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Reported drive efficiency trend in \(unit)")

                ChartLegend("Consumption per drive", color: TessalyticsTheme.warning)
            }
        }
    }
}

private struct WeekdayActivityChart: View {
    let points: [AnalyticsCategoryPoint]
    let distanceUnit: String

    private var resolvedDistanceUnit: String {
        distanceUnit.isEmpty ? UnitsDTO.metricDefaults.lengthSymbol : distanceUnit
    }

    var body: some View {
        SectionCard("Activity by weekday", subtitle: "Total distance", symbol: "calendar.badge.clock", tint: TessalyticsTheme.neutral) {
            if points.allSatisfy({ $0.value == 0 }) {
                ChartEmptyState(message: "No weekday distance data in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Weekday", point.label), y: .value("Distance", point.value))
                        .foregroundStyle(TessalyticsTheme.chartNeutral)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartXAxis {
                    AxisMarks { AxisValueLabel().font(.caption2) }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...max(1, (points.map(\.value).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Weekday", y: "Distance (\(resolvedDistanceUnit))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Distance by weekday in \(resolvedDistanceUnit)")

                ChartLegend("Total distance", color: TessalyticsTheme.chartNeutral)
            }
        }
    }
}

private struct TimeOfDayMixChart: View {
    let points: [AnalyticsCategoryPoint]

    private let colors: [String: Color] = [
        "Morning": TessalyticsTheme.warning,
        "Afternoon": TessalyticsTheme.accent,
        "Evening": TessalyticsTheme.chartNeutral,
        "Night": TessalyticsTheme.steel
    ]

    var body: some View {
        SectionCard("Trip timing", subtitle: "By local start time", symbol: "clock.badge") {
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
                    "Evening": TessalyticsTheme.chartNeutral,
                    "Night": TessalyticsTheme.steel
                ])
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text(number.formatted()).font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxisLabel(position: .bottom, alignment: .center) {
                    Text("Completed trips")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .tessalyticsChartStyle()
                .frame(height: 104)
                .accessibilityLabel("Trip count composition by time of day")

                LazyVGrid(
                    columns: TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.statMinWidth),
                    spacing: TessalyticsLayout.gridSpacing
                ) {
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
        SectionCard("Energy and cost", subtitle: "One point per charge", symbol: "circle.hexagongrid.fill", tint: TessalyticsTheme.neutral) {
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
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .tessalyticsChartAxes(
                    x: "Energy added (kWh)",
                    y: "Cost (\(Locale.current.currency?.identifier ?? "reported"))"
                )
                .chartForegroundStyleScale(range: [
                    TessalyticsTheme.accent,
                    TessalyticsTheme.chartNeutral,
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
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisValueLabel().font(.caption2)
                    }
                }
                .tessalyticsChartAxes(x: "\(valueLabel) (\(unit))", y: "")
                .tessalyticsChartStyle()
                .frame(height: max(170, CGFloat(points.count) * 42))
                .accessibilityLabel("\(title), values in \(unit)")

                ChartLegend("\(valueLabel) (\(unit))", color: tint)
            }
        }
    }
}

private struct AnalyticsCoverageCard: View {
    let coverage: AnalyticsCoverage

    var body: some View {
        SectionCard("Data coverage", subtitle: "Synchronized field completeness", symbol: "checkmark.seal.fill", tint: TessalyticsTheme.neutral) {
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
                Text(AppText.format("%1$@ of %2$@", "\(available)", "\(total)"))
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

/// The panel every analytics chart falls back to.
///
/// Carries the same closing sentence as the other still-filling-up panels: on a
/// new install most of this screen is empty at once, and eight identical-looking
/// blanks read as a broken screen unless they say what they are waiting for.
private struct ChartEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Label(message, systemImage: "chart.xyaxis.line")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ChartNeedsMoreHistory.reassurance)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

private struct AnalyticsSourceNote: View {
    let coverage: AnalyticsCoverage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("TeslaMate source data", systemImage: "externaldrive.connected.to.line.below")
                .font(.caption.weight(.semibold))
            Text("Missing values are excluded, not counted as zero.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let date = coverage?.latestActivity {
                Text(AppText.format("Latest activity %@", date.formatted(date: .abbreviated, time: .shortened)))
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
