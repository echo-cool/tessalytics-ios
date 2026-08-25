import Charts
import SwiftUI

//  The two dashboards TeslaMate's Grafana set has and this app did not: the
//  efficiency panels, which explain consumption by what the weather and the trip
//  were doing, and the mileage and statistics panels, which say how far the car
//  has gone, month by month, and where its time went.

// MARK: - Efficiency

struct EfficiencyAnalyticsDashboard: View {
    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?
    let distanceUnit: String
    let temperatureUnit: String

    private var consumptionUnit: String { distanceUnit.isEmpty ? "reported" : "Wh/\(distanceUnit)" }

    var body: some View {
        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
            MetricGrid {
                MetricCard(
                    title: "Consumption",
                    value: ValueFormatting.number(snapshot.summary.averageEfficiency, unit: consumptionUnit, digits: 0),
                    symbol: "leaf.fill",
                    detail: comparison(
                        snapshot.summary.averageEfficiency,
                        snapshot.previousSummary?.averageEfficiency,
                        label: comparisonLabel
                    ),
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Energy used",
                    value: ValueFormatting.number(driveEnergy, unit: "kWh", digits: 0),
                    symbol: "bolt.horizontal.fill",
                    detail: driveEnergy == nil ? nil : "While driving",
                    tint: TessalyticsTheme.accent
                )
                MetricCard(
                    title: "Cold penalty",
                    value: coldPenalty.map { "+\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "—",
                    symbol: "thermometer.snowflake",
                    detail: coldPenalty == nil ? "Needs a colder band" : "Coldest vs warmest",
                    tint: TessalyticsTheme.steel
                )
                MetricCard(
                    title: "Best month",
                    value: value(of: bestMonth),
                    symbol: "arrow.down.right",
                    detail: label(of: bestMonth),
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Worst month",
                    value: value(of: worstMonth),
                    symbol: "arrow.up.right",
                    detail: label(of: worstMonth),
                    tint: TessalyticsTheme.critical
                )
                MetricCard(
                    title: "Measured",
                    value: snapshot.coverage.drivesWithEfficiency.formatted(),
                    symbol: "checkmark.seal.fill",
                    detail: AppText.format("of %@ drives", "\(snapshot.coverage.drives)"),
                    tint: TessalyticsTheme.neutral
                )
            }

            ConsumptionByTemperatureChart(
                points: snapshot.efficiencyByTemperature,
                periodLabel: periodLabel,
                consumptionUnit: consumptionUnit,
                temperatureUnit: temperatureUnit
            )
            MonthlyConsumptionChart(points: snapshot.monthly, consumptionUnit: consumptionUnit)
            ConsumptionByDistanceChart(
                points: snapshot.consumptionByDistance,
                consumptionUnit: consumptionUnit,
                distanceUnit: distanceUnit
            )
        }
    }

    private var measuredMonths: [AnalyticsMonthlyPoint] {
        snapshot.monthly.filter { ($0.consumption ?? 0) > 0 }
    }

    private var bestMonth: AnalyticsMonthlyPoint? {
        measuredMonths.count > 1 ? measuredMonths.min { ($0.consumption ?? 0) < ($1.consumption ?? 0) } : nil
    }

    private var worstMonth: AnalyticsMonthlyPoint? {
        measuredMonths.count > 1 ? measuredMonths.max { ($0.consumption ?? 0) < ($1.consumption ?? 0) } : nil
    }

    private func value(of point: AnalyticsMonthlyPoint?) -> String {
        guard let consumption = point?.consumption else { return "—" }
        return ValueFormatting.number(consumption, unit: consumptionUnit, digits: 0)
    }

    private func label(of point: AnalyticsMonthlyPoint?) -> String? {
        point.map { $0.month.formatted(.dateTime.month(.wide)) } ?? "Needs two months"
    }

    private var driveEnergy: Double? {
        let total = snapshot.dailyDriving.map(\.energy).reduce(0, +)
        return total > 0 ? total : nil
    }

    /// How much more the coldest band uses than the warmest, as a percentage.
    private var coldPenalty: Double? {
        let bands = snapshot.efficiencyByTemperature.filter { $0.consumption > 0 && $0.drives >= 2 }
        guard bands.count >= 2, let coldest = bands.first, let warmest = bands.last,
              warmest.consumption > 0 else { return nil }
        let change = (coldest.consumption - warmest.consumption) / warmest.consumption * 100
        return change > 0 ? change : nil
    }
}

private struct ConsumptionByTemperatureChart: View {
    let points: [AnalyticsTemperaturePoint]
    let periodLabel: String
    let consumptionUnit: String
    let temperatureUnit: String

    var body: some View {
        SectionCard(
            "Consumption by temperature",
            subtitle: AppText.format("%1$@ · distance-weighted, %2$@", periodLabel, temperatureUnit),
            symbol: "thermometer.medium",
            tint: TessalyticsTheme.warning
        ) {
            if points.count < 2 {
                ChartEmptyState(message: "Needs drives in two temperature bands.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Temperature", point.label), y: .value("Consumption", point.consumption))
                        .foregroundStyle(TessalyticsTheme.warning)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
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
                .chartYScale(domain: 0...max(1, (points.map(\.consumption).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Outside temperature (\(temperatureUnit))", y: "Consumption (\(consumptionUnit))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Average consumption by outside temperature band")

                LazyVGrid(
                    columns: TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.statMinWidth),
                    spacing: TessalyticsLayout.gridSpacing
                ) {
                    ForEach(points) { point in
                        CompactStat(
                            title: point.label,
                            value: point.consumption.formatted(.number.precision(.fractionLength(0))),
                            detail: "\(point.drives) drives",
                            tint: TessalyticsTheme.warning
                        )
                    }
                }
            }
        }
    }
}

private struct MonthlyConsumptionChart: View {
    let points: [AnalyticsMonthlyPoint]
    let consumptionUnit: String

    private var measured: [AnalyticsMonthlyPoint] { points.filter { $0.consumption != nil } }

    var body: some View {
        SectionCard("Consumption by month", subtitle: "Distance-weighted", symbol: "calendar", tint: TessalyticsTheme.accent) {
            if measured.count < 2 {
                ChartEmptyState(message: "Needs two months of drives.")
            } else {
                Chart(measured) { point in
                    LineMark(x: .value("Month", point.month, unit: .month), y: .value("Consumption", point.consumption ?? 0))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.accent)
                    PointMark(x: .value("Month", point.month, unit: .month), y: .value("Consumption", point.consumption ?? 0))
                        .foregroundStyle(TessalyticsTheme.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
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
                .tessalyticsChartAxes(x: "Month", y: "Consumption (\(consumptionUnit))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Average consumption by month")

                ChartLegend("Monthly consumption", color: TessalyticsTheme.accent)
            }
        }
    }
}

private struct ConsumptionByDistanceChart: View {
    let points: [AnalyticsConsumptionPoint]
    let consumptionUnit: String
    let distanceUnit: String

    var body: some View {
        SectionCard(
            "Consumption by trip length",
            subtitle: "One point per drive",
            symbol: "circle.hexagongrid.fill",
            tint: TessalyticsTheme.neutral
        ) {
            if points.count < 12 {
                ChartEmptyState(message: "Needs 12 drives with both figures. \(points.count) so far.")
            } else {
                Chart(points) { point in
                    PointMark(x: .value("Distance", point.distance), y: .value("Consumption", point.consumption))
                        .foregroundStyle(TessalyticsTheme.chartNeutral.opacity(0.75))
                        .symbolSize(40)
                }
                .chartXScale(domain: 0...max(1, (points.map(\.distance).max() ?? 1) * 1.1))
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
                .tessalyticsChartAxes(x: "Trip distance (\(distanceUnit))", y: "Consumption (\(consumptionUnit))")
                .tessalyticsChartStyle()
                .frame(height: 240)
                .accessibilityLabel("Consumption against trip distance across \(points.count) drives")

                ChartLegend("One drive", color: TessalyticsTheme.chartNeutral)
            }
        }
    }
}

// MARK: - Mileage

struct MileageAnalyticsDashboard: View {
    let snapshot: AnalyticsDashboardSnapshot
    let periodLabel: String
    let comparisonLabel: String?
    let distanceUnit: String
    /// The live odometer, which reaches past the newest recorded drive.
    let odometer: Double?

    var body: some View {
        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
            MetricGrid {
                MetricCard(
                    title: "Odometer",
                    value: ValueFormatting.number(odometer ?? snapshot.odometerTrail.last?.odometer, unit: distanceUnit, digits: 0),
                    symbol: "gauge.open.with.lines.needle.33percent",
                    detail: "Latest reading",
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Distance",
                    value: ValueFormatting.number(snapshot.summary.distance, unit: distanceUnit, digits: 0),
                    symbol: "road.lanes",
                    detail: comparison(snapshot.summary.distance, snapshot.previousSummary?.distance, label: comparisonLabel)
                )
                MetricCard(
                    title: "Per day",
                    value: ValueFormatting.number(dailyAverage, unit: distanceUnit, digits: 0),
                    symbol: "calendar.day.timeline.left",
                    detail: dailyAverage == nil ? nil : "Across the period",
                    tint: TessalyticsTheme.steel
                )
                MetricCard(
                    title: "Yearly pace",
                    value: ValueFormatting.number(dailyAverage.map { $0 * 365 }, unit: distanceUnit, digits: 0),
                    symbol: "arrow.up.forward",
                    detail: dailyAverage == nil ? nil : "At this rate",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Trips",
                    value: snapshot.summary.driveCount.formatted(),
                    symbol: "car.side.fill",
                    detail: comparison(
                        Double(snapshot.summary.driveCount),
                        snapshot.previousSummary.map { Double($0.driveCount) },
                        label: comparisonLabel
                    ),
                    tint: TessalyticsTheme.accent
                )
                MetricCard(
                    title: "Driving time",
                    value: ValueFormatting.duration(minutes: snapshot.summary.drivingMinutes),
                    symbol: "timer",
                    detail: snapshot.timeSplit.isMeasurable
                        ? ValueFormatting.percentage(snapshot.timeSplit.share(snapshot.timeSplit.drivingMinutes), digits: 1)
                        : nil,
                    tint: TessalyticsTheme.warning
                )
            }

            OdometerTrailChart(points: snapshot.odometerTrail, periodLabel: periodLabel, distanceUnit: distanceUnit)
            MonthlyDistanceChart(points: snapshot.monthly, distanceUnit: distanceUnit)
            MonthlyEnergyChart(points: snapshot.monthly)
            TimeSplitCard(split: snapshot.timeSplit)
        }
    }

    /// Distance per day over the days the period actually covers.
    private var dailyAverage: Double? {
        guard let distance = snapshot.summary.distance, snapshot.timeSplit.spanMinutes > 0 else { return nil }
        let days = Double(snapshot.timeSplit.spanMinutes) / (60 * 24)
        return days >= 1 ? distance / days : nil
    }
}

private struct OdometerTrailChart: View {
    let points: [AnalyticsOdometerPoint]
    let periodLabel: String
    let distanceUnit: String

    var body: some View {
        SectionCard("Odometer", subtitle: periodLabel, symbol: "chart.line.uptrend.xyaxis", tint: TessalyticsTheme.neutral) {
            if points.count < 3 {
                ChartEmptyState(message: "Needs three drives reporting an odometer.")
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Odometer", point.odometer))
                        .interpolationMethod(.monotone)
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
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                // A focused scale: an odometer sits far from zero and a zero
                // baseline would flatten a year of driving into a level line.
                .chartYScale(domain: domain)
                .tessalyticsChartAxes(x: "Date", y: "Odometer (\(distanceUnit))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Odometer over time in \(distanceUnit)")

                ChartLegend("Odometer", color: TessalyticsTheme.chartNeutral)
            }
        }
    }

    private var domain: ClosedRange<Double> {
        let values = points.map(\.odometer)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.08, 1)
        return (low - padding)...(high + padding)
    }
}

private struct MonthlyDistanceChart: View {
    let points: [AnalyticsMonthlyPoint]
    let distanceUnit: String

    var body: some View {
        SectionCard("Distance by month", subtitle: "Completed drives", symbol: "chart.bar.fill") {
            if points.isEmpty {
                ChartEmptyState(message: "No drives in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Month", point.month, unit: .month), y: .value("Distance", point.distance))
                        .foregroundStyle(TessalyticsTheme.accent)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
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
                .tessalyticsChartAxes(x: "Month", y: "Distance (\(distanceUnit))")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Distance driven by month in \(distanceUnit)")

                ChartLegend("Distance", color: TessalyticsTheme.accent)
            }
        }
    }
}

private struct MonthlyEnergyChart: View {
    let points: [AnalyticsMonthlyPoint]

    private var priced: [AnalyticsMonthlyPoint] { points.filter { $0.chargingCost > 0 } }

    var body: some View {
        SectionCard("Charging by month", subtitle: "Energy added", symbol: "bolt.fill", tint: TessalyticsTheme.positive) {
            if points.allSatisfy({ $0.chargingEnergy == 0 }) {
                ChartEmptyState(message: "No charging sessions in this period.")
            } else {
                Chart(points) { point in
                    BarMark(x: .value("Month", point.month, unit: .month), y: .value("Energy added", point.chargingEnergy))
                        .foregroundStyle(TessalyticsTheme.positive)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
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
                .chartYScale(domain: 0...max(1, (points.map(\.chargingEnergy).max() ?? 1) * 1.12))
                .tessalyticsChartAxes(x: "Month", y: "Energy (kWh)")
                .tessalyticsChartStyle()
                .frame(height: 220)
                .accessibilityLabel("Charging energy by month in kilowatt-hours")

                if !priced.isEmpty {
                    LazyVGrid(
                        columns: TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.statMinWidth),
                        spacing: TessalyticsLayout.gridSpacing
                    ) {
                        ForEach(priced.suffix(6)) { point in
                            CompactStat(
                                title: point.month.formatted(.dateTime.month(.abbreviated).year(.twoDigits)),
                                value: ValueFormatting.chargeCost(point.chargingCost),
                                detail: ValueFormatting.number(point.chargingEnergy, unit: "kWh", digits: 0),
                                tint: TessalyticsTheme.positive
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct TimeSplitCard: View {
    let split: AnalyticsTimeSplit

    private var slices: [(label: String, minutes: Int, color: Color)] {
        [
            ("Driving", split.drivingMinutes, TessalyticsTheme.accent),
            ("Charging", split.chargingMinutes, TessalyticsTheme.positive),
            ("Parked", split.idleMinutes, TessalyticsTheme.steel)
        ]
    }

    var body: some View {
        SectionCard("Where the time went", subtitle: "Across the period", symbol: "clock.badge.checkmark", tint: TessalyticsTheme.steel) {
            if !split.isMeasurable {
                ChartEmptyState(message: "No activity in this period.")
            } else {
                Chart(slices, id: \.label) { slice in
                    BarMark(x: .value("Minutes", slice.minutes), y: .value("Period", "Time"))
                        .foregroundStyle(by: .value("State", slice.label))
                }
                .chartForegroundStyleScale([
                    "Driving": TessalyticsTheme.accent,
                    "Charging": TessalyticsTheme.positive,
                    "Parked": TessalyticsTheme.steel
                ])
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .tessalyticsChartStyle()
                .frame(height: 104)
                .accessibilityLabel("Share of the period spent driving, charging and parked")

                LazyVGrid(
                    columns: TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.statMinWidth),
                    spacing: TessalyticsLayout.gridSpacing
                ) {
                    ForEach(slices, id: \.label) { slice in
                        CompactStat(
                            title: slice.label,
                            value: ValueFormatting.duration(minutes: slice.minutes),
                            detail: ValueFormatting.percentage(split.share(slice.minutes), digits: 1),
                            tint: slice.color
                        )
                    }
                }
            }
        }
    }
}
