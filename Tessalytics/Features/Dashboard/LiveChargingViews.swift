import Charts
import SwiftUI

/// What is happening at the charger, and what will have happened by the time the
/// owner comes back.
///
/// The counterpart of `LiveDriveSection`, and deliberately the same shape: a
/// figures card, then charts. What differs is that a drive is watched and a
/// charge is left — so the figures lead with a forecast rather than a total, and
/// the chart's most useful half is the part that has not happened yet.
struct LiveChargeSection: View {
    let session: LiveChargeSession
    let projection: ChargeProjection?
    let status: VehicleStatus?
    let units: UnitsDTO?

    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }

    var body: some View {
        Group {
            figures
            if let projection, !projection.isComplete {
                // The forecast chart itself is in the hero card, where the
                // question it answers is being asked. This is the detail behind
                // it.
                ChargeMilestoneList(projection: projection)
            }
        }
        // No identifier on the Group. One here is applied to every child and
        // overrides the identifiers the cards set for themselves, so both of them
        // became "live-charge-section" and neither could be found by name.
    }

    private var figures: some View {
        SectionCard(
            "This charge",
            subtitle: spanLabel,
            symbol: "bolt.fill",
            tint: TessalyticsTheme.positive
        ) {
            MetricGrid {
                MetricCard(
                    title: "In an hour",
                    value: hourAhead,
                    symbol: "clock.arrow.circlepath",
                    detail: hourAheadDetail,
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Charging at",
                    value: ValueFormatting.number(status?.chargingDetails?.reportedPower, unit: "kW", digits: 1),
                    symbol: "bolt.fill",
                    detail: rateDetail,
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Added",
                    value: ValueFormatting.number(session.energyAdded, unit: "kWh", digits: 1),
                    symbol: "battery.100percent.bolt",
                    detail: gainedDetail,
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Full at",
                    value: completesText,
                    symbol: "flag.checkered",
                    detail: completesDetail,
                    tint: TessalyticsTheme.accentBright
                )
            }
        }
        // A container, not a bare identifier: on a card full of figures a plain
        // identifier is inherited by every one of them and finds nothing.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-charge-figures")
    }

    /// The answer to "can I leave in an hour, and with what?"
    private var hourAhead: String {
        guard let projection else { return "—" }
        return "\(Int(projection.level(after: 3_600).rounded()))%"
    }

    private var hourAheadDetail: String? {
        guard let projection else { return nil }
        let gain = projection.level(after: 3_600) - projection.level
        guard gain >= 0.5 else { return "Already at the limit" }
        return "+\(Int(gain.rounded())) points from \(Int(projection.level.rounded()))%"
    }

    /// The measured rate, said plainly, and whether it is falling.
    ///
    /// Worth showing beside the power because they are different facts: 150 kW is
    /// what the cabinet is delivering, and 40 %/h is what it is doing to this pack.
    private var rateDetail: String? {
        guard let projection, projection.initialRate > 0 else { return nil }
        let rate = "\(Int(projection.initialRate.rounded()))%/h"
        return projection.isTapering ? "\(rate) · slowing" : rate
    }

    private var gainedDetail: String? {
        guard let gained = session.levelGained, gained >= 1 else { return nil }
        var detail = "+\(Int(gained.rounded())) points"
        if let range = session.rangeGained, range >= 1 {
            detail += " · \(ValueFormatting.distance(range, units: resolvedUnits, digits: 0))"
        }
        return detail
    }

    private var completesText: String {
        guard let date = projection?.completesAt else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var completesDetail: String? {
        guard let projection, let date = projection.completesAt else { return nil }
        let minutes = max(Int(date.timeIntervalSince(projection.start) / 60), 1)
        return "\(Int(projection.limit.rounded()))% · \(ValueFormatting.duration(minutes: minutes)) away"
    }

    private var spanLabel: String {
        guard let elapsed = session.duration, elapsed >= 60 else { return "Waiting for readings" }
        return "So far · \(ValueFormatting.duration(minutes: max(Int(elapsed / 60), 1)))"
    }
}

/// When each round number arrives.
///
/// The list a chart cannot replace: someone planning around a charge wants a
/// clock time for the percentage they actually need, not a curve to read one off.
struct ChargeMilestoneList: View {
    let projection: ChargeProjection

    private var milestones: [ChargeProjection.Milestone] { projection.milestones() }

    var body: some View {
        if !milestones.isEmpty {
            SectionCard(
                "When it reaches",
                subtitle: projection.isTapering
                    ? "Allowing for the rate falling as the pack fills"
                    : "At the rate it is charging now",
                symbol: "clock",
                tint: TessalyticsTheme.accentBright
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                        if index > 0 { Divider() }
                        row(milestone)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("charge-milestones")
        }
    }

    private func row(_ milestone: ChargeProjection.Milestone) -> some View {
        HStack(spacing: 12) {
            Text("\(Int(milestone.percent.rounded()))%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)
            Text(waitLabel(milestone))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(milestone.date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(milestone.percent.rounded())) percent")
        .accessibilityValue(
            "at \(milestone.date.formatted(date: .omitted, time: .shortened)), \(waitLabel(milestone))"
        )
    }

    private func waitLabel(_ milestone: ChargeProjection.Milestone) -> String {
        let minutes = max(Int(milestone.date.timeIntervalSince(projection.start) / 60), 0)
        if minutes < 1 { return "now" }
        return "in \(ValueFormatting.duration(minutes: minutes))"
    }
}

/// The forecast, drawn where the question is asked.
///
/// This sits inside the hero card, in the place the seven-day battery chart holds
/// when the car is not plugged in. A week of history is the right thing to show a
/// parked car and the wrong thing to show one on a charger: the question has
/// changed from "how has it been doing" to "when can I leave".
///
/// Two axes, because charge and power are the two things happening and they are
/// not the same shape. Charge climbs and flattens; power holds and then falls
/// away, and it is the fall in power that *causes* the flattening. Drawn on one
/// axis, either the power line is a flat smear along the bottom or the charge line
/// is squashed into the top — and the relationship between them, which is the
/// whole explanation for why the last ten percent takes as long as the first
/// thirty, disappears.
struct HeroChargeForecast: View {
    let session: LiveChargeSession
    let projection: ChargeProjection

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let percent: Double
        let power: Double?
    }

    private var observed: [Point] {
        session.samples.enumerated().map {
            Point(id: $0.offset, date: $0.element.date, percent: $0.element.level, power: $0.element.power)
        }
    }

    private var forecast: [Point] {
        projection.curve(through: 6 * 3_600).map {
            Point(id: 10_000 + $0.id, date: $0.date, percent: $0.percent, power: $0.power)
        }
    }

    /// Charge and power share one scale, because Swift Charts has one.
    ///
    /// The power series is mapped onto the charge axis for drawing and the right
    /// hand axis is labelled with the inverse, so the numbers a reader sees on
    /// each side are the real ones in their own units.
    private var powerCeiling: Double {
        let powers = (observed.compactMap(\.power) + forecast.compactMap(\.power))
        let peak = powers.max() ?? 0
        guard peak > 0 else { return 0 }
        // Rounded up to something with a readable label on it.
        let step: Double = peak > 60 ? 50 : (peak > 20 ? 20 : 5)
        return max((peak / step).rounded(.up) * step, step)
    }

    private var showsPower: Bool { powerCeiling > 0 }

    /// Round kilowatt values inside the visible range, for the right-hand axis.
    private var powerTicks: [Double] {
        guard powerCeiling > 0 else { return [] }
        let step = powerCeiling / 4
        return (0...4).map { Double($0) * step }
    }

    private func scaled(_ power: Double) -> Double {
        guard powerCeiling > 0 else { return chargeDomain.lowerBound }
        let fraction = min(max(power / powerCeiling, 0), 1)
        return chargeDomain.lowerBound + fraction * (chargeDomain.upperBound - chargeDomain.lowerBound)
    }

    private func unscaled(_ value: Double) -> Double {
        let span = chargeDomain.upperBound - chargeDomain.lowerBound
        guard span > 0 else { return 0 }
        return (value - chargeDomain.lowerBound) / span * powerCeiling
    }

    /// Never the full nought-to-a-hundred: a charge from 60 to 80 drawn on a
    /// full-height axis is a flat line with nothing to read.
    private var chargeDomain: ClosedRange<Double> {
        let levels = observed.map(\.percent) + forecast.map(\.percent) + [projection.limit]
        let low = max((levels.min() ?? 0) - 5, 0)
        let high = min((levels.max() ?? 100) + 5, 100)
        guard high - low >= 15 else { return max(high - 15, 0)...min(max(high - 15, 0) + 15, 100) }
        return low...high
    }

    /// A little room past the last point, so the rightmost time label is not
    /// drawn half outside the card and clipped.
    private var timeDomain: ClosedRange<Date> {
        let dates = observed.map(\.date) + forecast.map(\.date)
        guard let first = dates.min(), let last = dates.max(), last > first else {
            return projection.start.addingTimeInterval(-600)...projection.start.addingTimeInterval(3_600)
        }
        return first...last.addingTimeInterval(last.timeIntervalSince(first) * 0.07)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline
            chart
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hero-charge-forecast")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            figure(value: "\(Int(projection.level(after: 3_600).rounded()))%", label: "in an hour")
            if let completes = projection.completesAt {
                Divider().frame(height: 26)
                figure(
                    value: completes.formatted(date: .omitted, time: .shortened),
                    label: "at \(Int(projection.limit.rounded()))%"
                )
            }
            Spacer(minLength: 0)
            if projection.isTapering {
                Label("slowing", systemImage: "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func figure(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            if showsPower {
                // Behind the charge lines, and lighter: power is the explanation,
                // charge is the answer.
                ForEach(observed.filter { $0.power != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Power", scaled(point.power ?? 0)),
                        series: .value("Kind", "power measured")
                    )
                    .foregroundStyle(TessalyticsTheme.warning.opacity(0.75))
                    .lineStyle(.init(lineWidth: 1.6, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
                ForEach(forecast.filter { $0.power != nil }) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Power", scaled(point.power ?? 0)),
                        series: .value("Kind", "power forecast")
                    )
                    .foregroundStyle(TessalyticsTheme.warning.opacity(0.55))
                    .lineStyle(.init(lineWidth: 1.6, lineCap: .round, dash: [3, 3]))
                    .interpolationMethod(.monotone)
                }
            }

            // Two named series, not two sets of marks. Without the series value
            // Swift Charts joins every LineMark sharing the x and y roles into one
            // line and one style — which drew the forecast solid, in the measured
            // line's colour, erasing the only thing that separates a reading from
            // a guess.
            ForEach(observed) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Charge", point.percent),
                    series: .value("Kind", "charge measured")
                )
                .foregroundStyle(TessalyticsTheme.positive)
                .lineStyle(.init(lineWidth: 2.4, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            ForEach(forecast) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Charge", point.percent),
                    series: .value("Kind", "charge forecast")
                )
                .foregroundStyle(TessalyticsTheme.accentBright)
                .lineStyle(.init(lineWidth: 2.4, lineCap: .round, dash: [5, 4]))
                .interpolationMethod(.monotone)
            }

            RuleMark(y: .value("Limit", projection.limit))
                .foregroundStyle(.secondary.opacity(0.40))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
            RuleMark(x: .value("Now", projection.start))
                .foregroundStyle(.secondary.opacity(0.28))
                .lineStyle(.init(lineWidth: 1))
                .annotation(position: .top, alignment: .center, spacing: 1) {
                    Text("now").font(.system(size: 8)).foregroundStyle(.secondary)
                }

            // Where the session began, so the measured half has a beginning as
            // well as an end. Without it the solid line just starts somewhere,
            // and how long the car has been on the charger — the thing that makes
            // the rate believable — is left to be inferred from the axis.
            if let startedAt = session.startedAt, startedAt < projection.start {
                RuleMark(x: .value("Started", startedAt))
                    .foregroundStyle(TessalyticsTheme.positive.opacity(0.35))
                    .lineStyle(.init(lineWidth: 1, dash: [2, 2]))
                    .annotation(position: .top, alignment: .leading, spacing: 1) {
                        Text("plugged in \(startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: chargeDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                            .font(.system(size: 9))
                            .foregroundStyle(TessalyticsTheme.positive)
                    }
                }
            }
            if showsPower {
                // Explicit positions, so the labels are round kilowatts rather
                // than whatever the charge axis happened to tick at — "139 kW"
                // and "51 kW" are the charge axis showing through, and mean
                // nothing to anyone.
                AxisMarks(position: .trailing, values: powerTicks.map(scaled)) { value in
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text("\(Int(unscaled(raw).rounded())) kW")
                                .font(.system(size: 9))
                                .foregroundStyle(TessalyticsTheme.warning)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
        .padding(.top, 10)
        .accessibilityLabel("Charge forecast")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("charge-forecast-chart")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            key(colour: TessalyticsTheme.positive, text: "charge", dashed: false)
            key(colour: TessalyticsTheme.accentBright, text: "forecast", dashed: true)
            if showsPower {
                key(colour: TessalyticsTheme.warning, text: "power", dashed: false)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func key(colour: Color, text: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(colour.opacity(dashed ? 0.55 : 1))
                .frame(width: 12, height: 2.5)
            Text(text).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: String {
        let hour = Int(projection.level(after: 3_600).rounded())
        var sentence = ""
        if let startedAt = session.startedAt {
            sentence += "plugged in at \(startedAt.formatted(date: .omitted, time: .shortened)), "
        }
        sentence += "\(Int(projection.level.rounded())) percent now, \(hour) percent in an hour"
        if let completes = projection.completesAt {
            sentence += ", \(Int(projection.limit.rounded())) percent at "
                + completes.formatted(date: .omitted, time: .shortened)
        }
        if let power = projection.power(at: projection.level) {
            sentence += ", drawing \(Int(power.rounded())) kilowatts"
        }
        return sentence
    }
}
