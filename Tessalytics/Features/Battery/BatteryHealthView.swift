import Charts
import SwiftData
import SwiftUI

struct BatteryHealthView: View {
    var embedded = false

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var observation: BatteryHealthRecord?
    @State private var observations: [BatteryHealthRecord] = []
    @State private var loading = true
    @State private var message: String?
    @State private var capacityObservations: [CapacityObservation] = []
    @State private var capacityMedians: [CapacityObservation] = []
    @State private var projectedRange: [ProjectedRangePoint] = []

    /// The effective figures: the owner's rating when they supplied one, and the
    /// derived estimate otherwise.
    private var effective: FleetStatistics.BatteryHealth? { environment.fleet.battery }
    private var capacityNew: Double? { effective?.capacityNew ?? observation?.maxCapacity }
    private var maxRangeNew: Double? { effective?.maxRangeNew ?? observation?.maxRange }
    private var healthPercent: Double? { effective?.healthPercent ?? observation?.healthPercent }

    /// The page itself, without the scroll view around it.
    ///
    /// Factored out so the shared image is the same content the screen shows
    /// rather than a second rendering of it that can drift.
    @ViewBuilder private var pageContent: some View {
        if let observation {
            BatteryHealthHero(health: healthPercent)
            BatteryMetricGrid(
                observation: observation,
                units: environment.statusUnits,
                capacityNew: capacityNew,
                maxRangeNew: maxRangeNew,
                isOwnerRated: effective?.isSpecificationOverridden == true
            )
            CapacityByMileageChart(
                observations: capacityObservations,
                medians: capacityMedians,
                capacityNew: capacityNew,
                units: environment.statusUnits
            )
            ProjectedRangeChart(
                points: projectedRange,
                units: environment.statusUnits,
                maxRangeNew: maxRangeNew
            )
            BatteryCapacityChart(observation: observation, capacityNew: capacityNew)
            BatteryRangeChart(observation: observation, units: environment.statusUnits, maxRangeNew: maxRangeNew)
            if observations.count > 1 {
                BatteryHealthTrendChart(observations: observations)
            }
            if !embedded {
                BatteryEstimateNote(observedAt: observation.observedAt)
            }
        }
    }

    /// What the share carries in words, for the places a picture is not enough.
    private func sharePage() -> SharePage {
        let units = environment.statusUnits
        var highlights: [ShareHighlight] = []
        if let healthPercent {
            highlights.append(.init(label: "health", value: ValueFormatting.percentage(healthPercent / 100, digits: 1)))
        }
        if let capacityNew {
            highlights.append(.init(label: "capacity when new", value: ValueFormatting.number(capacityNew, unit: "kWh", digits: 1)))
        }
        if let now = observation?.currentCapacity {
            highlights.append(.init(label: "capacity now", value: ValueFormatting.number(now, unit: "kWh", digits: 1)))
        }
        if let maxRangeNow = observation?.currentRange {
            highlights.append(.init(label: "range at 100%", value: ValueFormatting.distance(maxRangeNow, units: units, digits: 0)))
        }

        var sentences = ["Battery health for \(environment.selectedVehicle?.name?.nilIfEmpty ?? "my Tesla")."]
        if let healthPercent, let capacityNew, let now = observation?.currentCapacity {
            sentences.append(
                "The pack holds \(ValueFormatting.number(now, unit: "kWh", digits: 1)) of the "
                + "\(ValueFormatting.number(capacityNew, unit: "kWh", digits: 1)) it had when new — "
                + "\(ValueFormatting.percentage(healthPercent / 100, digits: 1)) retained."
            )
        }
        sentences.append("Measured from charging history by Tessalytics.")
        return SharePage(
            title: "Battery health",
            subtitle: SharePage.subtitle(car: environment.selectedVehicle?.name),
            highlights: highlights,
            summary: sentences.joined(separator: " ")
        )
    }


    var body: some View {
        TessalyticsScreen(showsTopAccent: !embedded) {
            ScrollView {
                if loading {
                    LoadingPanel(title: "Estimating battery health", symbol: "battery.75percent")
                        .padding()
                } else if observation != nil {
                    LazyVStack(spacing: 12) { pageContent }
                        .tessalyticsScreenPadding()
                        .tessalyticsReadableWidth()
                } else {
                    EmptyState(
                        title: "Battery health unavailable",
                        message: message ?? "Not enough charging history yet for an estimate.",
                        symbol: "battery.0percent"
                    )
                }
            }
        }
        .navigationTitle(embedded ? "Analysis" : "Battery health")
        .shareablePage(sharePage) { VStack(spacing: 12) { pageContent } }
        .task { await load() }
        // Recompute whenever a history sync lands new charges.
        .task(id: environment.historyRevision) { rebuildSeries() }
        .refreshable {
            await fetch()
            await environment.refreshHistory()
            rebuildSeries()
        }
        .accessibilityIdentifier("battery-health-screen")
    }

    private func load() async {
        if environment.isDemoMode {
            // Read the observations DemoExperience seeded rather than inventing a
            // second fixture. The previous inline copy carried a rated efficiency
            // of 0.158, off by a factor of 100 — it is kWh per 100 km, not per
            // mile — which made every modelled capacity implausible and left the
            // capacity-by-mileage chart empty.
            let server = (environment.selectedProfile?.id ?? DemoExperience.profileID).uuidString
            let car = environment.selectedVehicle?.id ?? DemoExperience.carID
            observations = (try? context.fetch(FetchDescriptor<BatteryHealthRecord>(
                predicate: #Predicate { $0.serverID == server && $0.carID == car },
                sortBy: [SortDescriptor(\.observedAt)]
            ))) ?? []
            observation = observations.last
            rebuildSeries()
            loading = false
            return
        }

        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            loading = false
            return
        }
        let server = profile.id.uuidString
        let car = vehicle.id
        var latestDescriptor = FetchDescriptor<BatteryHealthRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == car },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        observations = (try? context.fetch(FetchDescriptor<BatteryHealthRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == car },
            sortBy: [SortDescriptor(\.observedAt)]
        ))) ?? []
        observation = try? context.fetch(latestDescriptor).first
        rebuildSeries()
        if let observation, Date().timeIntervalSince(observation.observedAt) < 86_400 {
            loading = false
        } else {
            await fetch()
        }
    }

    /// Builds the capacity and projected-range series from cached history.
    private func rebuildSeries() {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            capacityObservations = []
            capacityMedians = []
            projectedRange = []
            return
        }
        let charges = ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        let drives = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        // The rated efficiency comes from the battery-health endpoint and is what
        // turns a range reading back into kilowatt-hours.
        let efficiency = observation?.ratedEfficiency ?? environment.fleet.battery?.ratedEfficiency
        capacityObservations = CapacityModel.observations(
            charges: charges,
            ratedEfficiency: efficiency,
            units: environment.statusUnits
        )
        capacityMedians = CapacityModel.semiMonthlyMedians(capacityObservations)
        projectedRange = ProjectedRangeModel.points(drives: drives, charges: charges)
    }

    private func fetch() async {
        guard !environment.isDemoMode else { return }
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            loading = false
            return
        }
        loading = true
        defer { loading = false }
        do {
            let dto = try await environment.client(for: profile).batteryHealth(carID: vehicle.id).batteryHealth
            let record = BatteryHealthRecord(serverID: profile.id, carID: vehicle.id, dto: dto)
            context.insert(record)
            try context.save()
            observation = record
            if !observations.contains(where: { $0.cacheKey == record.cacheKey }) {
                observations.append(record)
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct BatteryHealthHero: View {
    let health: Double?

    private var value: Double { health ?? 0 }
    private var tint: Color {
        if value >= 90 { return TessalyticsTheme.positive }
        if value >= 80 { return TessalyticsTheme.warning }
        return TessalyticsTheme.critical
    }

    var body: some View {
        SurfaceCard(tint: tint) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { content }
                VStack(spacing: 12) { content }
            }
        }
    }

    @ViewBuilder private var content: some View {
        Gauge(value: value, in: 0...100) {
            Text("Estimated health")
        } currentValueLabel: {
            Text(health.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                .font(.title3.bold())
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(tint)
        .scaleEffect(1.12)
        .frame(width: 100, height: 100)

        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated battery condition")
                .font(.title2.bold())
            StatusBadge(text: "Estimate · not a diagnostic", color: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct BatteryMetricGrid: View {
    let observation: BatteryHealthRecord
    let units: UnitsDTO?
    let capacityNew: Double?
    let maxRangeNew: Double?
    let isOwnerRated: Bool

    var body: some View {
        MetricGrid {
            MetricCard(
                title: isOwnerRated ? "Rated capacity" : "Modeled capacity",
                value: ValueFormatting.number(capacityNew, unit: "kWh"),
                symbol: "battery.100percent",
                detail: "When new",
                tint: TessalyticsTheme.positive
            )
            MetricCard(
                title: "Current capacity",
                value: ValueFormatting.number(observation.currentCapacity, unit: "kWh"),
                symbol: "battery.75percent",
                detail: capacityDetail,
                tint: TessalyticsTheme.positive
            )
            MetricCard(
                title: isOwnerRated ? "Rated range" : "Modeled range",
                value: ValueFormatting.distance(maxRangeNew, units: units, digits: 0),
                symbol: "arrow.up.right",
                detail: "At 100% when new",
                tint: TessalyticsTheme.neutral
            )
            MetricCard(
                title: "Current range",
                value: ValueFormatting.distance(observation.currentRange, units: units, digits: 0),
                symbol: "car.side.fill",
                detail: rangeDetail,
                tint: TessalyticsTheme.neutral
            )
        }
    }

    /// How much of the modelled-new figure remains, and the absolute shortfall —
    /// far more useful than repeating the raw kWh with no reference point.
    private var capacityDetail: String {
        guard let maximum = capacityNew, maximum > 0,
              let current = observation.currentCapacity else { return "Estimated" }
        let lost = maximum - current
        guard lost > 0.05 else { return "No measurable loss" }
        return "\(percent(current / maximum)) · -\(ValueFormatting.number(lost, unit: "kWh"))"
    }

    private var rangeDetail: String {
        guard let maximum = maxRangeNew, maximum > 0,
              let current = observation.currentRange else { return "Estimated" }
        let lost = maximum - current
        guard lost > 0.5 else { return "No measurable loss" }
        return "\(percent(current / maximum)) · -\(ValueFormatting.distance(lost, units: units, digits: 0))"
    }

    private func percent(_ ratio: Double) -> String {
        (ratio * 100).formatted(.number.precision(.fractionLength(0))) + "% of new"
    }
}

private struct BatteryComparisonPoint: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

private struct BatteryCapacityChart: View {
    let observation: BatteryHealthRecord
    let capacityNew: Double?

    private var points: [BatteryComparisonPoint] {
        [
            capacityNew.map { BatteryComparisonPoint(label: "When new", value: $0) },
            observation.currentCapacity.map { BatteryComparisonPoint(label: "Current", value: $0) }
        ].compactMap { $0 }
    }

    var body: some View {
        SectionCard("Capacity comparison", subtitle: "Estimated, kWh", symbol: "battery.100percent", tint: TessalyticsTheme.positive) {
            if points.count < 2 {
                Text("Both maximum and current estimates are needed for comparison.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Capacity", point.value), y: .value("Estimate", point.label))
                        .foregroundStyle(point.label == "Current" ? TessalyticsTheme.positive : TessalyticsTheme.steel.opacity(0.45))
                        .clipShape(.rect(cornerRadius: 5))
                        .annotation(position: .trailing) {
                            Text("\(point.value.formatted(.number.precision(.fractionLength(1)))) kWh")
                                .font(.caption2.monospacedDigit())
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
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(.caption2) } }
                .tessalyticsChartAxes(x: "Usable capacity (kWh)", y: "")
                .tessalyticsChartStyle()
                .frame(height: 150)
                .accessibilityLabel("Estimated maximum and current battery capacity")

                ChartLegend([
                    .init("Current estimate", color: TessalyticsTheme.positive),
                    .init("Modeled when new", color: TessalyticsTheme.steel.opacity(0.45))
                ])
            }
        }
    }
}

private struct BatteryRangeChart: View {
    let observation: BatteryHealthRecord
    let units: UnitsDTO?
    let maxRangeNew: Double?

    private var distanceUnit: String { (units ?? .metricDefaults).lengthSymbol }

    private var points: [BatteryComparisonPoint] {
        [
            maxRangeNew.map { BatteryComparisonPoint(label: "When new", value: $0) },
            observation.currentRange.map { BatteryComparisonPoint(label: "Current", value: $0) }
        ].compactMap { $0 }
    }

    var body: some View {
        SectionCard("Range comparison", subtitle: AppText.format("Estimated, %@", distanceUnit), symbol: "point.bottomleft.forward.to.point.topright.scurvepath", tint: TessalyticsTheme.neutral) {
            if points.count < 2 {
                Text("Needs both a maximum and a current estimate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Range", point.value), y: .value("Estimate", point.label))
                        .foregroundStyle(point.label == "Current" ? TessalyticsTheme.accent : TessalyticsTheme.steel.opacity(0.45))
                        .clipShape(.rect(cornerRadius: 5))
                        .annotation(position: .trailing) {
                            Text("\(point.value.formatted(.number.precision(.fractionLength(0...1)))) \(distanceUnit)")
                                .font(.caption2.monospacedDigit())
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
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(.caption2) } }
                .tessalyticsChartAxes(x: "Range (\(distanceUnit))", y: "")
                .tessalyticsChartStyle()
                .frame(height: 150)
                .accessibilityLabel("Estimated maximum and current battery range in \(distanceUnit)")

                ChartLegend([
                    .init("Current estimate", color: TessalyticsTheme.accent),
                    .init("Modeled when new", color: TessalyticsTheme.steel.opacity(0.45))
                ])
            }
        }
    }
}

private struct BatteryHealthTrendChart: View {
    let observations: [BatteryHealthRecord]

    var body: some View {
        SectionCard("Estimated health trend", subtitle: "Daily", symbol: "chart.xyaxis.line", tint: TessalyticsTheme.positive) {
            Chart(observations, id: \.cacheKey) { value in
                if let health = value.healthPercent {
                    LineMark(x: .value("Date", value.observedAt), y: .value("Estimated health", health))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.positive)
                    PointMark(x: .value("Date", value.observedAt), y: .value("Estimated health", health))
                        .foregroundStyle(TessalyticsTheme.positive)
                }
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
                            Text(number.formatted(.number.precision(.fractionLength(0...1))))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .tessalyticsChartAxes(x: "Observation date", y: "Estimated health (%)")
            .tessalyticsChartStyle()
            .frame(height: 220)
            .accessibilityLabel("Estimated battery health trend over \(observations.count) observations")

            ChartLegend("Estimated health", color: TessalyticsTheme.positive)
        }
    }
}

private struct BatteryEstimateNote: View {
    let observedAt: Date

    var body: some View {
        SectionCard("Estimated, not measured", subtitle: AppText.format("Updated %@", ValueFormatting.date(observedAt)), symbol: "info.circle.fill", tint: TessalyticsTheme.warning) {
            Text("Derived from charging and range data. Temperature and calibration shift the numbers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
