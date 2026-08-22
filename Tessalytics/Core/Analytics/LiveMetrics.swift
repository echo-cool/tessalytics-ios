import Foundation

/// One live figure, already formatted, with enough about it for a view to draw it
/// without knowing where it came from.
struct LiveMetric: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable { case accent, positive, warning, neutral }

    let id: String
    let value: String
    let label: String
    let symbol: String
    var tone: Tone = .neutral
}

/// The figures shown while the car is moving.
///
/// Built here rather than in the views so that both the card on the home screen
/// and the full-screen map show the same numbers, formatted the same way, and so
/// that "0 mph" versus "Unavailable" is a decision a test can pin down.
enum LiveMetrics {
    /// The six that fill the grid on the hero card.
    ///
    /// Deliberately none of battery level, range or the odometer: those are drawn
    /// as the ring and the two figures directly above this grid, and a card that
    /// says the same number twice wastes the half of it that could have said
    /// something else.
    static func hero(
        status: VehicleStatus?,
        totals: LiveDriveTotals,
        units: UnitsDTO?
    ) -> [LiveMetric] {
        let units = units ?? .metricDefaults
        return [
            speed(status, units),
            power(status),
            distance(totals, units),
            energyUsed(totals),
            outsideTemperature(status, units),
            elevation(status)
        ]
    }

    /// The fuller set for the map, which has the room and no ring gauge on it.
    static func expanded(
        status: VehicleStatus?,
        totals: LiveDriveTotals,
        units: UnitsDTO?
    ) -> [LiveMetric] {
        let units = units ?? .metricDefaults
        return [
            speed(status, units),
            power(status),
            batteryLevel(status),
            range(status, units),
            distance(totals, units),
            energyUsed(totals),
            consumption(totals, units),
            outsideTemperature(status, units),
            elevation(status),
            heading(status)
        ]
    }

    // MARK: - Individual figures

    static func speed(_ status: VehicleStatus?, _ units: UnitsDTO) -> LiveMetric {
        LiveMetric(
            id: "speed",
            value: ValueFormatting.speed(status?.liveSpeed, units: units, digits: 0),
            label: "speed",
            symbol: "speedometer",
            tone: .accent
        )
    }

    static func power(_ status: VehicleStatus?) -> LiveMetric {
        let watts = status?.livePower
        let isRegenerating = (watts ?? 0) < 0
        return LiveMetric(
            id: "power",
            value: ValueFormatting.number(watts, unit: "kW", digits: 0),
            label: isRegenerating ? "regenerating" : "power",
            symbol: "bolt.fill",
            tone: isRegenerating ? .positive : .warning
        )
    }

    static func batteryLevel(_ status: VehicleStatus?) -> LiveMetric {
        LiveMetric(
            id: "battery",
            value: status?.batteryDetails?.batteryLevel.map { "\($0)%" } ?? "Unavailable",
            label: "battery",
            symbol: "battery.75percent",
            tone: .positive
        )
    }

    static func range(_ status: VehicleStatus?, _ units: UnitsDTO) -> LiveMetric {
        let reading = status?.batteryDetails?.displayRange
        return LiveMetric(
            id: "range",
            value: ValueFormatting.distance(reading?.value, units: units, digits: 0),
            label: reading?.label ?? "range",
            symbol: "gauge.open.with.lines.needle.33percent",
            tone: .accent
        )
    }

    /// Taken from the drive's totals, not from the chart buffer.
    ///
    /// The buffer is a rolling window of about eight minutes on a streaming
    /// drive, so "this drive" read from it was the last eight minutes of a
    /// forty-mile journey.
    static func distance(_ totals: LiveDriveTotals, _ units: UnitsDTO) -> LiveMetric {
        LiveMetric(
            id: "distance",
            value: ValueFormatting.distance(totals.distance, units: units, digits: 1),
            label: "this drive",
            symbol: "arrow.left.and.right",
            tone: .accent
        )
    }

    static func energyUsed(_ totals: LiveDriveTotals) -> LiveMetric {
        LiveMetric(
            id: "energy",
            value: ValueFormatting.number(totals.energyUsed, unit: "kWh", digits: 1),
            label: "energy used",
            symbol: "bolt.batteryblock.fill",
            tone: .positive
        )
    }

    static func consumption(_ totals: LiveDriveTotals, _ units: UnitsDTO) -> LiveMetric {
        let value = totals.consumption
        return LiveMetric(
            id: "consumption",
            value: value.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Wh/\(units.lengthSymbol)" } ?? "—",
            label: "consumption",
            symbol: "leaf.fill",
            tone: .positive
        )
    }

    static func outsideTemperature(_ status: VehicleStatus?, _ units: UnitsDTO) -> LiveMetric {
        LiveMetric(
            id: "outside",
            value: ValueFormatting.temperature(status?.climateDetails?.outsideTemp, units: units, digits: 0),
            label: "outside",
            symbol: "thermometer.medium",
            tone: .neutral
        )
    }

    /// Which way the car is pointing.
    ///
    /// The arrow on the map already says it, but only to someone looking at the
    /// map: the readout is what a driver reads without taking their eyes far off
    /// the road, and "NE" is a faster read than an arrow's angle.
    static func heading(_ status: VehicleStatus?) -> LiveMetric {
        let degrees = status?.drivingDetails?.heading
        let point = CompassPoint.name(for: degrees)
        return LiveMetric(
            id: "heading",
            value: point.map { name in
                degrees.map { "\(name) · \($0.formatted(.number.precision(.fractionLength(0))))°" } ?? name
            } ?? "—",
            label: "heading",
            symbol: "location.north.line.fill",
            tone: .neutral
        )
    }

    static func elevation(_ status: VehicleStatus?) -> LiveMetric {
        LiveMetric(
            id: "elevation",
            value: status?.drivingDetails?.elevation
                .map { "\($0.formatted(.number.precision(.fractionLength(0)))) m" } ?? "—",
            label: "elevation",
            symbol: "mountain.2.fill",
            tone: .neutral
        )
    }
}
