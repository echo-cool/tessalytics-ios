import Charts
import SwiftUI

/// Modelled pack capacity against mileage.
///
/// Each point is one charge: the rated range and charge level at the end of the
/// session, converted back into a pack capacity. The scatter is noisy by nature —
/// temperature and how full the pack was both skew a single reading — so a
/// semi-monthly median is drawn through it, which is the line worth reading.
struct CapacityByMileageChart: View {
    let observations: [CapacityObservation]
    let medians: [CapacityObservation]
    let capacityNew: Double?
    let units: UnitsDTO?
    /// False when a surrounding card already carries the title, so the chart is
    /// not introduced twice.
    var showsHeader = true

    private var distanceUnit: String { (units ?? .metricDefaults).lengthSymbol }

    /// The mileage actually covered, not zero-to-latest.
    ///
    /// Degradation is read across the range the odometer has travelled. Letting
    /// the scale start at zero spends most of the plot on mileage the car had
    /// before any of these readings existed.
    private var odometerDomain: ClosedRange<Double> {
        let values = (observations + medians).map(\.odometer)
        guard let low = values.min(), let high = values.max(), high > low else { return 0...1 }
        let padding = (high - low) * 0.05
        return (low - padding)...(high + padding)
    }

    /// Compact notation rounds to whole thousands, so a car logged across a
    /// narrow band renders every tick as the same "18K". The precision follows
    /// the span rather than being fixed.
    private func odometerLabel(_ odometer: Double) -> String {
        let span = odometerDomain.upperBound - odometerDomain.lowerBound
        guard odometer >= 1_000 else {
            return odometer.formatted(.number.precision(.fractionLength(0)))
        }
        let digits = span < 2_000 ? 2 : (span < 12_000 ? 1 : 0)
        return "\((odometer / 1_000).formatted(.number.precision(.fractionLength(digits))))K"
    }

    private var capacityDomain: ClosedRange<Double> {
        let values = observations.map(\.capacity) + medians.map(\.capacity) + [capacityNew].compactMap { $0 }
        guard let low = values.min(), let high = values.max(), high > low else { return 0...100 }
        let padding = max((high - low) * 0.15, 1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        if showsHeader {
            SectionCard(
                "Battery capacity by mileage",
                subtitle: "Modeled — read the median, not the points",
                symbol: "chart.dots.scatter",
                tint: TessalyticsTheme.positive
            ) {
                chart
            }
        } else {
            chart
        }
    }

    @ViewBuilder private var chart: some View {
        Group {
            if observations.count < 4 {
                ChartUnavailable(
                    message: "Needs 4+ charges with a range reading — \(observations.count) so far."
                )
            } else {
                Chart {
                    if let capacityNew {
                        RuleMark(y: .value("When new", capacityNew))
                            .foregroundStyle(TessalyticsTheme.steel.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("When new")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    ForEach(observations) { point in
                        PointMark(
                            x: .value("Odometer", point.odometer),
                            y: .value("Capacity", point.capacity)
                        )
                        .foregroundStyle(TessalyticsTheme.positive.opacity(0.28))
                        .symbolSize(22)
                    }

                    ForEach(medians) { point in
                        LineMark(
                            x: .value("Odometer", point.odometer),
                            y: .value("Median capacity", point.capacity)
                        )
                        .foregroundStyle(TessalyticsTheme.positive)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: capacityDomain)
                .chartXScale(domain: odometerDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel {
                            if let odometer = value.as(Double.self) {
                                Text(odometerLabel(odometer))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let capacity = value.as(Double.self) {
                                Text(capacity.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .tessalyticsChartAxes(x: "Odometer (\(distanceUnit))", y: "Usable capacity (kWh)")
                .tessalyticsChartStyle()
                .frame(height: 250)
                .accessibilityLabel("Modeled battery capacity against odometer")
                .accessibilityValue(retentionSummary)
                .accessibilityIdentifier("capacity-by-mileage-chart")

                ChartLegend([
                    .init("Per charge", color: TessalyticsTheme.positive.opacity(0.28)),
                    .init("Semi-monthly median", color: TessalyticsTheme.positive),
                    .init("When new", color: TessalyticsTheme.steel.opacity(0.6))
                ])
            }
        }
    }

    private var retentionSummary: String {
        guard let latest = medians.last?.capacity, let capacityNew, capacityNew > 0 else {
            return "\(observations.count) observations"
        }
        return "\(ValueFormatting.percentage(latest / capacityNew, digits: 1)) of as-new capacity"
    }

}

/// Rated range extrapolated to a full charge, over time.
struct ProjectedRangeChart: View {
    let points: [ProjectedRangePoint]
    let units: UnitsDTO?
    let maxRangeNew: Double?

    private var distanceUnit: String { (units ?? .metricDefaults).lengthSymbol }

    /// Range varies by a few percent, so a domain anchored at zero compresses
    /// the whole series into a band at the top of the plot.
    private var rangeDomain: ClosedRange<Double> {
        let values = points.map(\.projectedRange) + [maxRangeNew].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        let padding = max((high - low) * 0.2, 5)
        return max(low - padding, 0)...(high + padding)
    }

    var body: some View {
        SectionCard(
            "Projected range",
            subtitle: "Rated range at 100%, weekly",
            symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
            tint: TessalyticsTheme.accent
        ) {
            if points.count < 3 {
                ChartUnavailable(
                    message: "At least three weeks of range readings are needed. \(points.count) available."
                )
            } else {
                Chart {
                    if let maxRangeNew {
                        RuleMark(y: .value("When new", maxRangeNew))
                            .foregroundStyle(TessalyticsTheme.steel.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Projected range", point.projectedRange)
                        )
                        .foregroundStyle(TessalyticsTheme.accent)
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Projected range", point.projectedRange)
                        )
                        .foregroundStyle(TessalyticsTheme.accent)
                        .symbolSize(18)
                    }
                }
                .chartYScale(domain: rangeDomain)
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
                            if let range = value.as(Double.self) {
                                Text(range.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .tessalyticsChartAxes(x: "Week", y: "Projected range (\(distanceUnit))")
                .tessalyticsChartStyle()
                .frame(height: 230)
                .accessibilityLabel("Projected range at a full charge over time, in \(distanceUnit)")
                .accessibilityIdentifier("projected-range-chart")

                ChartLegend([
                    .init("Projected", color: TessalyticsTheme.accent),
                    .init("When new", color: TessalyticsTheme.steel.opacity(0.6))
                ])
            }
        }
    }
}

/// Shared "not enough data" panel for the capacity charts.
struct ChartUnavailable: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 110)
            .multilineTextAlignment(.center)
    }
}
