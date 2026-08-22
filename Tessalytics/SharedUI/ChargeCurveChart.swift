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
    /// Small form for a list row.
    ///
    /// Still labelled. It used to be the two shapes and nothing else, which left
    /// a reader to guess that one line was a percentage, the other kilowatts, and
    /// the horizontal axis time — three guesses for a chart that fits in a
    /// thumbnail. The ticks are pared back to the ends of each scale rather than
    /// dropped.
    ///
    /// Compact is now a shorter chart, not a narrower one: a row gives it the
    /// full width of the card, the same as a drive row gives its map. Squeezed
    /// into a 138-point column beside the text, the axis labels took more of the
    /// space than the lines did.
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
            .chartYAxis {
                AxisMarks(position: .leading, values: isCompact ? [0, 100] : [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            // The unit rides on the top tick in the small form,
                            // where repeating it four times would not fit.
                            Text(isCompact && percent < 100 ? "\(Int(percent))" : "\(Int(percent))%")
                                .font(axisFont)
                                .foregroundStyle(TessalyticsTheme.positive)
                        }
                    }
                }
                // The same positions, labelled back in kilowatts.
                AxisMarks(position: .trailing, values: isCompact ? [0, 100] : [0, 25, 50, 75, 100]) { value in
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            let kilowatts = Int((percent / 100 * powerCeiling).rounded())
                            Text(isCompact && percent < 100 ? "\(kilowatts)" : "\(kilowatts)\(isCompact ? "kW" : "")")
                                .font(axisFont)
                                .foregroundStyle(TessalyticsTheme.warning)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: isCompact ? 3 : 4)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisTick()
                    // Labelled in both forms now. The clock times used to truncate
                    // to "9:3…", which is why the small form replaced them with a
                    // span in the legend; at the full width of a card they fit.
                    AxisValueLabel(format: .dateTime.hour().minute()).font(axisFont)
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery level and charging power over the session")
            .accessibilityValue(accessibilityValue)

            if isCompact {
                microLegend
            } else {
                HStack(spacing: 14) {
                    ChartLegend("Battery level (%)", color: TessalyticsTheme.positive)
                    ChartLegend("Charging power (kW)", color: TessalyticsTheme.warning)
                }
                Text("Time of day along the bottom; level on the left axis, power on the right.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var axisFont: Font {
        isCompact ? .system(size: 8, weight: .medium).monospacedDigit() : .caption2.monospacedDigit()
    }

    /// Which line is which, and what the horizontal axis is, in the width a
    /// thumbnail has.
    private var microLegend: some View {
        HStack(spacing: 8) {
            swatch(TessalyticsTheme.positive, "level %")
            swatch(TessalyticsTheme.warning, "power kW")
            Spacer(minLength: 2)
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Capsule().fill(color).frame(width: 9, height: 3)
            Text(label).foregroundStyle(.secondary)
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
