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

    var body: some View {
        TessalyticsScreen(showsTopAccent: !embedded) {
            ScrollView {
                if loading {
                    LoadingPanel(title: "Estimating battery health", symbol: "battery.75percent")
                        .padding()
                } else if let observation {
                    LazyVStack(spacing: 12) {
                        BatteryHealthHero(observation: observation)
                        BatteryMetricGrid(observation: observation)
                        BatteryCapacityChart(observation: observation)
                        BatteryRangeChart(observation: observation)
                        if observations.count > 1 {
                            BatteryHealthTrendChart(observations: observations)
                        }
                        if !embedded {
                            BatteryEstimateNote(observedAt: observation.observedAt)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    EmptyState(
                        title: "Battery health unavailable",
                        message: message ?? "TeslaMateApi has not reported enough data for an estimate.",
                        symbol: "battery.0percent"
                    )
                }
            }
        }
        .navigationTitle(embedded ? "Analysis" : "Battery health")
        .task { await load() }
        .refreshable { await fetch() }
        .accessibilityIdentifier("battery-health-screen")
    }

    private func load() async {
        if environment.isDemoMode {
            let calendar = Calendar.current
            observations = (0..<9).compactMap { index in
                guard let date = calendar.date(byAdding: .month, value: index - 8, to: .now) else { return nil }
                let health = 96.8 - Double(index) * 0.22
                return BatteryHealthRecord(
                    serverID: environment.selectedProfile?.id ?? UUID(),
                    carID: environment.selectedVehicle?.id ?? 1,
                    dto: BatteryHealthDTO(
                        maxRange: 310,
                        currentRange: 310 * health / 100,
                        maxCapacity: 78.4,
                        currentCapacity: 78.4 * health / 100,
                        ratedEfficiency: 0.158,
                        batteryHealthPercentage: health
                    ),
                    date: date
                )
            }
            observation = observations.last
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
        if let observation, Date().timeIntervalSince(observation.observedAt) < 86_400 {
            loading = false
        } else {
            await fetch()
        }
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
    let observation: BatteryHealthRecord

    private var health: Double { observation.healthPercent ?? 0 }
    private var tint: Color {
        if health >= 90 { return TessalyticsTheme.positive }
        if health >= 80 { return TessalyticsTheme.warning }
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
        Gauge(value: health, in: 0...100) {
            Text("Estimated health")
        } currentValueLabel: {
            Text(observation.healthPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
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
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            MetricCard(title: "Maximum estimate", value: ValueFormatting.number(observation.maxCapacity, unit: "kWh"), symbol: "battery.100percent", tint: TessalyticsTheme.positive)
            MetricCard(title: "Current estimate", value: ValueFormatting.number(observation.currentCapacity, unit: "kWh"), symbol: "battery.75percent", tint: TessalyticsTheme.positive)
            MetricCard(title: "Maximum range", value: ValueFormatting.number(observation.maxRange, unit: ""), symbol: "arrow.up.right", tint: TessalyticsTheme.neutral)
            MetricCard(title: "Current range", value: ValueFormatting.number(observation.currentRange, unit: ""), symbol: "car.side.fill", tint: TessalyticsTheme.neutral)
        }
    }
}

private struct BatteryComparisonPoint: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

private struct BatteryCapacityChart: View {
    let observation: BatteryHealthRecord

    private var points: [BatteryComparisonPoint] {
        [
            observation.maxCapacity.map { BatteryComparisonPoint(label: "Modeled max", value: $0) },
            observation.currentCapacity.map { BatteryComparisonPoint(label: "Current", value: $0) }
        ].compactMap { $0 }
    }

    var body: some View {
        SectionCard("Capacity comparison", subtitle: "TeslaMate estimate · kilowatt-hours", symbol: "battery.100percent", tint: TessalyticsTheme.positive) {
            if points.count < 2 {
                Text("Both maximum and current estimates are needed for comparison.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Capacity", point.value), y: .value("Estimate", point.label))
                        .foregroundStyle(point.label == "Current" ? TessalyticsTheme.positive : Color.secondary.opacity(0.35))
                        .clipShape(.rect(cornerRadius: 5))
                        .annotation(position: .trailing) {
                            Text("\(point.value.formatted(.number.precision(.fractionLength(1)))) kWh")
                                .font(.caption2.monospacedDigit())
                        }
                }
                .chartXScale(domain: 0...max(1, (points.map(\.value).max() ?? 1) * 1.2))
                .chartXAxis { AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) }
                .tessalyticsChartStyle()
                .frame(height: 150)
                .accessibilityLabel("Estimated maximum and current battery capacity")
            }
        }
    }
}

private struct BatteryRangeChart: View {
    let observation: BatteryHealthRecord

    private var points: [BatteryComparisonPoint] {
        [
            observation.maxRange.map { BatteryComparisonPoint(label: "Modeled max", value: $0) },
            observation.currentRange.map { BatteryComparisonPoint(label: "Current", value: $0) }
        ].compactMap { $0 }
    }

    var body: some View {
        SectionCard("Range comparison", subtitle: "Reported range estimate in TeslaMate distance units", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", tint: TessalyticsTheme.neutral) {
            if points.count < 2 {
                Text("Both maximum and current range estimates are needed for comparison.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Range", point.value), y: .value("Estimate", point.label))
                        .foregroundStyle(point.label == "Current" ? TessalyticsTheme.accent : Color.secondary.opacity(0.35))
                        .clipShape(.rect(cornerRadius: 5))
                        .annotation(position: .trailing) {
                            Text(point.value.formatted(.number.precision(.fractionLength(0...1))))
                                .font(.caption2.monospacedDigit())
                        }
                }
                .chartXScale(domain: 0...max(1, (points.map(\.value).max() ?? 1) * 1.2))
                .chartXAxis { AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) }
                .tessalyticsChartStyle()
                .frame(height: 150)
                .accessibilityLabel("Estimated maximum and current battery range")
            }
        }
    }
}

private struct BatteryHealthTrendChart: View {
    let observations: [BatteryHealthRecord]

    var body: some View {
        SectionCard("Estimated health trend", subtitle: "Daily observations · focused scale", symbol: "chart.xyaxis.line", tint: TessalyticsTheme.positive) {
            Chart(observations, id: \.cacheKey) { value in
                if let health = value.healthPercent {
                    LineMark(x: .value("Date", value.observedAt), y: .value("Estimated health", health))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.positive)
                    PointMark(x: .value("Date", value.observedAt), y: .value("Estimated health", health))
                        .foregroundStyle(TessalyticsTheme.positive)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .tessalyticsChartStyle()
            .frame(height: 220)
            .accessibilityLabel("Estimated battery health trend over \(observations.count) observations")
        }
    }
}

private struct BatteryEstimateNote: View {
    let observedAt: Date

    var body: some View {
        SectionCard("How to read this", subtitle: "Updated \(ValueFormatting.date(observedAt))", symbol: "info.circle.fill", tint: TessalyticsTheme.warning) {
            Text("These are TeslaMateApi estimates derived from recent charging and range data—not physical battery-capacity measurements. Temperature, calibration, driving history, and data completeness can affect them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
