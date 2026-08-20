import Charts
import MapKit
import SwiftUI

/// Where the car is now, pointing the way it is facing.
///
/// A drive is the one time a map earns space on the home screen: the number on
/// the speedometer says how fast, and only the map says where.
struct LiveLocationMap: View {
    let coordinate: CLLocationCoordinate2D
    var heading: Double?
    var trail: [CLLocationCoordinate2D] = []
    var height: CGFloat = 132

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera, interactionModes: []) {
            if trail.count > 1 {
                MapPolyline(coordinates: trail)
                    .stroke(TessalyticsTheme.accentBright.opacity(0.85), lineWidth: 3)
            }
            Annotation("", coordinate: coordinate) {
                ZStack {
                    Circle()
                        .fill(TessalyticsTheme.accentBright.opacity(0.22))
                        .frame(width: 34, height: 34)
                    Image(systemName: heading == nil ? "circle.fill" : "location.north.fill")
                        .font(.system(size: heading == nil ? 11 : 15, weight: .bold))
                        .foregroundStyle(TessalyticsTheme.accentBright)
                        .rotationEffect(.degrees(heading ?? 0))
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(.rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous))
        .allowsHitTesting(false)
        .onChange(of: coordinate.latitude) { _, _ in follow() }
        .onChange(of: coordinate.longitude) { _, _ in follow() }
        .task { follow() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current location on a map")
    }

    /// Recentres as the car moves. The span is fixed: an automatic camera would
    /// rescale on every reading and make the map appear to breathe.
    private func follow() {
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        }
    }
}

/// The badge that says readings are arriving as they happen.
struct LiveIndicator: View {
    let isStreaming: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isStreaming ? TessalyticsTheme.accentBright : TessalyticsTheme.steel)
                .frame(width: 7, height: 7)
                .opacity(pulsing && isStreaming ? 0.35 : 1)
                .animation(
                    isStreaming ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                    value: pulsing
                )
            Text(isStreaming ? "LIVE" : "RECONNECTING")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(isStreaming ? TessalyticsTheme.accentBright : TessalyticsTheme.steel)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (isStreaming ? TessalyticsTheme.accentBright : TessalyticsTheme.steel).opacity(0.14),
            in: .capsule
        )
        .task { pulsing = true }
        .accessibilityLabel(isStreaming ? "Live" : "Reconnecting")
    }
}

/// The cards that only make sense while the car is moving.
///
/// Built for a phone on a mount: large figures, and charts covering the last few
/// minutes rather than the last few months.
struct LiveDriveSection: View {
    let buffer: LiveTelemetryBuffer
    let units: UnitsDTO?

    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }
    private var speedUnit: String { resolvedUnits.speedSymbol }
    private var distanceUnit: String { resolvedUnits.lengthSymbol }

    var body: some View {
        Group {
            liveMetrics
            if buffer.samples.count > 2 {
                speedChart
                powerChart
            }
        }
    }

    private var liveMetrics: some View {
        SectionCard("This drive", subtitle: spanLabel, symbol: "location.north.line.fill", tint: TessalyticsTheme.accentBright) {
            MetricGrid {
                MetricCard(
                    title: "Distance",
                    value: ValueFormatting.distance(buffer.distance, units: resolvedUnits, digits: 1),
                    symbol: "arrow.left.and.right",
                    tint: TessalyticsTheme.accentBright
                )
                MetricCard(
                    title: "Top speed",
                    value: ValueFormatting.speed(buffer.maximumSpeed, units: resolvedUnits, digits: 0),
                    symbol: "speedometer",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Energy used",
                    value: ValueFormatting.number(buffer.energyUsed, unit: "kWh", digits: 2),
                    symbol: "bolt.fill",
                    detail: "Net of regen",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Consumption",
                    value: buffer.consumption().map { "\($0.formatted(.number.precision(.fractionLength(0)))) Wh/\(distanceUnit)" } ?? "—",
                    symbol: "leaf.fill",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Peak power",
                    value: ValueFormatting.number(buffer.maximumPower, unit: "kW", digits: 0),
                    symbol: "arrow.up.right",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Peak regen",
                    value: ValueFormatting.number(buffer.maximumRegeneration, unit: "kW", digits: 0),
                    symbol: "arrow.down.right",
                    tint: TessalyticsTheme.positive
                )
            }
        }
    }

    private var spanLabel: String {
        guard let span = buffer.span else { return "Waiting for readings" }
        return "Last \(ValueFormatting.duration(minutes: max(Int(span / 60), 1)))"
    }

    private var speedChart: some View {
        SectionCard("Speed", subtitle: "Live", symbol: "speedometer", tint: TessalyticsTheme.accentBright) {
            Chart(buffer.samples) { sample in
                if let speed = sample.speed {
                    AreaMark(x: .value("Time", sample.date), y: .value("Speed", speed), stacking: .unstacked)
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [TessalyticsTheme.accentBright.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Time", sample.date), y: .value("Speed", speed))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.accentBright)
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
            .tessalyticsChartAxes(x: "Time", y: "Speed (\(speedUnit))")
            .tessalyticsChartStyle()
            .frame(height: 150)
            .accessibilityLabel("Speed over the last few minutes")
            .accessibilityValue(ValueFormatting.speed(buffer.latest?.speed, units: resolvedUnits, digits: 0))
        }
    }

    /// Power keeps zero on the axis and shows regeneration below it, because the
    /// sign is the interesting part.
    private var powerChart: some View {
        SectionCard("Power", subtitle: "Negative is regeneration", symbol: "bolt.fill", tint: TessalyticsTheme.warning) {
            Chart(buffer.samples) { sample in
                if let power = sample.power {
                    BarMark(x: .value("Time", sample.date), y: .value("Power", power))
                        .foregroundStyle(power < 0 ? TessalyticsTheme.positive : TessalyticsTheme.warning)
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
            .tessalyticsChartAxes(x: "Time", y: "Power (kW)")
            .tessalyticsChartStyle()
            .frame(height: 150)
            .accessibilityLabel("Power over the last few minutes, with regeneration below zero")
            .accessibilityValue(ValueFormatting.number(buffer.latest?.power, unit: "kW", digits: 0))

            HStack(spacing: 14) {
                ChartLegend("Drawing", color: TessalyticsTheme.warning)
                ChartLegend("Regenerating", color: TessalyticsTheme.positive)
            }
        }
    }
}
