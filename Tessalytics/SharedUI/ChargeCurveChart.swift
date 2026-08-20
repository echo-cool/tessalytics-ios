import Charts
import SwiftUI

/// One instant of a charging session.
struct ChargeCurvePoint: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let level: Double?
    let power: Double?
}

/// A charging session as its two halves of one story.
///
/// The level climbing and the power tapering are the same event seen twice, and
/// reading them as separate charts means holding one shape in your head while
/// looking at the other. Together, the moment the taper begins lines up with the
/// level it began at, which is the thing worth knowing about a session.
///
/// Swift Charts has no second value axis, so power is mapped onto the percentage
/// scale and a trailing axis is labelled back in kilowatts. That is a real
/// constraint of the framework, not a shortcut: the alternative is two stacked
/// plots that no longer share an x position.
struct ChargeCurveChart: View {
    let points: [ChargeCurvePoint]
    /// Peak power, which sets the right-hand scale. Taken from the session summary
    /// when there is one, so a row and its detail screen agree.
    var peakPower: Double?
    var height: CGFloat = 200
    /// Compact form for a list row: no axes, no legend, just the two shapes.
    var isCompact = false

    private var powerCeiling: Double {
        let observed = points.compactMap(\.power).max() ?? 0
        // Rounded up to a sensible step so the axis reads 60, 120, 180 rather
        // than 58.7.
        let ceiling = max(peakPower ?? 0, observed, 1)
        return (ceiling / 20).rounded(.up) * 20
    }

    private func scaled(_ power: Double) -> Double { power / powerCeiling * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(points) { point in
                    if let level = point.level {
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Battery", level),
                            stacking: .unstacked
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [TessalyticsTheme.positive.opacity(0.2), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                ForEach(points) { point in
                    if let level = point.level {
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Battery", level),
                            series: .value("Series", "level")
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.positive)
                    }
                }
                ForEach(points) { point in
                    if let power = point.power {
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Power", scaled(power)),
                            series: .value("Series", "power")
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.warning)
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(isCompact ? .hidden : .automatic)
            .chartYAxis {
                if !isCompact {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int(percent))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(TessalyticsTheme.positive)
                            }
                        }
                    }
                    // The same positions, labelled back in kilowatts.
                    AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int((percent / 100 * powerCeiling).rounded()))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(TessalyticsTheme.warning)
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                if !isCompact {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute()).font(.caption2)
                    }
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery level and charging power over the session")
            .accessibilityValue(accessibilityValue)

            if !isCompact {
                HStack(spacing: 14) {
                    ChartLegend("Battery level (%)", color: TessalyticsTheme.positive)
                    ChartLegend("Charging power (kW)", color: TessalyticsTheme.warning)
                }
            }
        }
    }

    private var accessibilityValue: String {
        let levels = points.compactMap(\.level)
        let powers = points.compactMap(\.power)
        var parts: [String] = []
        if let first = levels.first, let last = levels.last {
            parts.append("level \(Int(first)) to \(Int(last)) percent")
        }
        if let peak = powers.max() {
            parts.append("peak \(Int(peak)) kilowatts")
        }
        return parts.isEmpty ? "No samples" : parts.joined(separator: ", ")
    }
}

extension ChargeDetailDTO {
    /// The session's samples as curve points, thinned for drawing.
    func curvePoints(limit: Int = 160) -> [ChargeCurvePoint] {
        let raw = chargeDetails.enumerated().compactMap { index, point -> ChargeCurvePoint? in
            guard let date = point.date?.value else { return nil }
            return ChargeCurvePoint(
                id: index,
                date: date,
                level: point.batteryLevel.map(Double.init),
                power: point.chargerDetails?.chargerPower
            )
        }
        guard raw.count > limit else { return raw }
        let stride = Int((Double(raw.count) / Double(limit)).rounded(.up))
        var thinned = raw.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
        if let last = raw.last, thinned.last?.id != last.id { thinned.append(last) }
        return thinned
    }
}
