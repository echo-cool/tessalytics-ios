import Charts
import MapKit
import SwiftUI

/// The drive so far, with the car at the end of it pointing the way it is facing.
///
/// A drive is the one time a map earns space on the home screen: the number on
/// the speedometer says how fast, and only the map says where. A pin alone barely
/// earns it — a coordinate is a place, and the road taken to get there is what
/// makes the place mean something.
struct LiveLocationMap: View {
    let coordinate: CLLocationCoordinate2D
    var heading: Double?
    /// The route, already stabilised. Passed as the whole value rather than as a
    /// coordinate array so the view can tell "the same line as last time" from "a
    /// line with a point added" without walking either of them.
    var route = LiveRouteTrail()
    var height: CGFloat?
    var isInteractive = false
    var followsCar = true

    @State private var camera: MapCameraPosition = .automatic
    /// What the camera was last pointed at, so it only moves when that changes.
    @State private var framing: LiveMapFraming?
    /// The drawn line, held as one MapKit object across redraws.
    ///
    /// `MapPolyline(coordinates:)` builds a new overlay from a new array every
    /// time the body runs — which, on a screen bound to a stream, is several times
    /// a second — and MapKit tears the old overlay down to put the new one up.
    /// That teardown is the flash. Holding the overlay and replacing it only when
    /// the route's revision changes means a redraw of the surrounding card costs
    /// the map nothing.
    @State private var line: MKPolyline?

    var body: some View {
        Map(position: $camera, interactionModes: isInteractive ? .all : []) {
            if let line, line.pointCount > 1 {
                // Under the coloured line, so the route reads against both a pale
                // and a dark map without either being tinted to suit it.
                MapPolyline(line)
                    .stroke(.black.opacity(0.18), style: .init(lineWidth: 6, lineCap: .round, lineJoin: .round))
                MapPolyline(line)
                    .stroke(
                        TessalyticsTheme.accentBright.opacity(0.9),
                        style: .init(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
            }
            if let start = route.coordinates.first, route.coordinates.count > 1 {
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
                ) {
                    Circle()
                        .fill(TessalyticsTheme.accentBright.opacity(0.55))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                }
                .annotationTitles(.hidden)
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
        .clipShape(.rect(cornerRadius: isInteractive ? 0 : TessalyticsTheme.compactRadius, style: .continuous))
        .allowsHitTesting(isInteractive)
        // Keyed on the revision, not on the coordinates: a reading that repeats
        // the car's position leaves both the overlay and the camera alone.
        .onChange(of: route.revision, initial: true) { _, _ in rebuildLine() }
        .onChange(of: coordinate.latitude) { _, _ in follow() }
        .onChange(of: coordinate.longitude) { _, _ in follow() }
        .onChange(of: followsCar) { _, isFollowing in
            guard isFollowing else { return }
            framing = nil
            follow()
        }
        .task { follow() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            route.coordinates.count > 1
                ? "The route driven so far, with the vehicle at the end of it"
                : "Current location on a map"
        )
    }

    private func rebuildLine() {
        let points = route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        line = points.count > 1 ? MKPolyline(coordinates: points, count: points.count) : nil
        follow()
    }

    private func follow() {
        guard followsCar else { return }
        let next = LiveMapCamera.framing(
            car: CoordinateDTO(latitude: coordinate.latitude, longitude: coordinate.longitude),
            trail: route.coordinates
        )
        // Re-animating a camera already looking at this is what made the map
        // wobble: every animation was cut off by the next reading's.
        guard LiveMapCamera.shouldMove(from: framing, to: next) else { return }
        framing = next
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: next.centerLatitude, longitude: next.centerLongitude),
                    span: MKCoordinateSpan(latitudeDelta: next.latitudeDelta, longitudeDelta: next.longitudeDelta)
                )
            )
        }
    }
}

/// What is steering, when the server reports it.
///
/// Drawn only from a reading. Most TeslaMate deployments publish nothing about
/// driving aids, and on those this view is never built at all — the app would
/// rather say nothing than guess at whether a car is driving itself, which is
/// not a thing to be wrong about in either direction.
struct SelfDrivingBadge: View {
    let mode: SelfDrivingMode

    /// Blue while something is steering, grey while nobody is. The app's own red
    /// is the colour of the car being live; this is the colour of the car driving
    /// itself, and they are not the same statement.
    private var color: Color {
        mode.isEngaged ? TessalyticsTheme.autopilot : TessalyticsTheme.steel
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: mode.symbol)
                .font(.caption2.weight(.bold))
                .symbolRenderingMode(.hierarchical)
            Text(mode.label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(mode.isEngaged ? 0.16 : 0.10), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.accessibilityDescription)
        .accessibilityIdentifier("self-driving-badge")
    }
}

/// The gear, as the car reports it.
///
/// One letter, because that is what is on the stalk and what the car publishes.
/// Drive is the unremarkable one and stays neutral; reverse and neutral are worth
/// a colour, and a car in neutral on a hill is worth noticing.
struct ShiftStateBadge: View {
    let gear: String

    private var normalised: String { gear.trimmingCharacters(in: .whitespaces).uppercased() }

    private var color: Color {
        switch normalised {
        case "P": TessalyticsTheme.steel
        case "D": TessalyticsTheme.accentBright
        case "R", "N": TessalyticsTheme.warning
        default: TessalyticsTheme.steel
        }
    }

    private var spokenName: String {
        switch normalised {
        case "P": "Park"
        case "D": "Drive"
        case "R": "Reverse"
        case "N": "Neutral"
        default: normalised
        }
    }

    var body: some View {
        Text(normalised)
            .font(.caption.weight(.bold))
            .monospaced()
            .frame(minWidth: 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gear")
            .accessibilityValue(spokenName)
            .accessibilityIdentifier("vehicle-shift-state")
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

extension LiveMetric.Tone {
    var color: Color {
        switch self {
        case .accent: TessalyticsTheme.accentBright
        case .positive: TessalyticsTheme.positive
        case .warning: TessalyticsTheme.warning
        case .neutral: TessalyticsTheme.steel
        }
    }
}

/// One live figure: a value, what it is, and an icon.
struct LiveMetricTile: View {
    let metric: LiveMetric

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: metric.symbol)
                .font(.caption)
                .foregroundStyle(metric.tone.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(metric.value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(metric.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.label)
        .accessibilityValue(metric.value)
        .accessibilityIdentifier("live-metric-\(metric.id)")
    }
}

/// The live figures, laid out to fill the grid rather than leave holes in it.
struct LiveMetricGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: [LiveMetric]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 104), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(metrics) { LiveMetricTile(metric: $0) }
        }
    }
}

/// The cards that only make sense while the car is moving.
///
/// Built for a phone on a mount: large figures, and charts covering the last few
/// minutes rather than the last few months.
struct LiveDriveSection: View {
    let buffer: LiveTelemetryBuffer
    /// The whole journey's figures. The buffer above is the last few minutes,
    /// which is right for a chart and wrong for a total.
    let totals: LiveDriveTotals
    let units: UnitsDTO?

    @AppStorage(LiveChartPreferences.metricsKey)
    private var storedMetrics = LiveChartPreferences.defaultEncodedMetrics
    @AppStorage(LiveChartPreferences.windowKey)
    private var storedWindowMinutes = LiveChartPreferences.defaultWindowMinutes

    private var preferences: LiveChartPreferences {
        LiveChartPreferences.decode(metrics: storedMetrics, windowMinutes: storedWindowMinutes)
    }
    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }
    private var distanceUnit: String { resolvedUnits.lengthSymbol }

    var body: some View {
        Group {
            liveMetrics
            if buffer.samples.count > 2 {
                let plotted = buffer.plotted(within: preferences.window)
                ForEach(preferences.metrics) { metric in
                    LiveMetricChart(
                        metric: metric,
                        samples: plotted,
                        units: resolvedUnits,
                        windowMinutes: preferences.windowMinutes
                    )
                }
            }
        }
    }

    private var liveMetrics: some View {
        SectionCard("This drive", subtitle: spanLabel, symbol: "location.north.line.fill", tint: TessalyticsTheme.accentBright) {
            MetricGrid {
                MetricCard(
                    title: "Distance",
                    value: ValueFormatting.distance(totals.distance, units: resolvedUnits, digits: 1),
                    symbol: "arrow.left.and.right",
                    tint: TessalyticsTheme.accentBright
                )
                MetricCard(
                    title: "Top speed",
                    value: ValueFormatting.speed(totals.maximumSpeed, units: resolvedUnits, digits: 0),
                    symbol: "speedometer",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Energy used",
                    value: ValueFormatting.number(totals.energyUsed, unit: "kWh", digits: 2),
                    symbol: "bolt.fill",
                    detail: "Net of regen",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Consumption",
                    value: totals.consumption.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Wh/\(distanceUnit)" } ?? "—",
                    symbol: "leaf.fill",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Peak power",
                    value: ValueFormatting.number(totals.maximumPower, unit: "kW", digits: 0),
                    symbol: "arrow.up.right",
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Peak regen",
                    value: ValueFormatting.number(totals.maximumRegeneration, unit: "kW", digits: 0),
                    symbol: "arrow.down.right",
                    tint: TessalyticsTheme.positive
                )
            }
        }
    }

    /// How much of the drive these figures cover.
    ///
    /// "Last 8m" used to describe the charts *and* the totals beside them,
    /// because both came from the same pruned buffer. The totals now cover the
    /// whole drive the app has seen, so this says that instead.
    private var spanLabel: String {
        guard let elapsed = totals.elapsed else { return "Waiting for readings" }
        return "So far · \(ValueFormatting.duration(minutes: max(Int(elapsed / 60), 1)))"
    }
}

/// One of the live charts the owner asked for.
///
/// All four share a frame, an axis treatment and a window, so that turning one on
/// does not change how the others read. Power is the exception that earns its
/// exception: it keeps zero on the axis and draws regeneration below it, because
/// the sign is the interesting part.
private struct LiveMetricChart: View {
    let metric: LiveChartMetric
    let samples: [LiveTelemetrySample]
    let units: UnitsDTO
    let windowMinutes: Int

    private var points: [LiveTelemetrySample] { samples.filter { metric.reading(of: $0) != nil } }

    private var unitSymbol: String {
        switch metric {
        case .speed: units.speedSymbol
        case .power: "kW"
        case .batteryLevel: "%"
        case .elevation: "m"
        }
    }

    private var tint: Color {
        switch metric {
        case .speed: TessalyticsTheme.accentBright
        case .power: TessalyticsTheme.warning
        case .batteryLevel: TessalyticsTheme.positive
        case .elevation: TessalyticsTheme.steel
        }
    }

    var body: some View {
        SectionCard(
            metric.title,
            subtitle: "\(metric.subtitle) · last \(windowMinutes) min",
            symbol: metric.symbol,
            tint: tint
        ) {
            if points.isEmpty {
                ChartNeedsMoreHistory(needs: "a few readings of \(metric.title.lowercased())", symbol: metric.symbol)
            } else {
                chart
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
                    .tessalyticsChartAxes(x: "", y: "\(metric.title) (\(unitSymbol))")
                    .tessalyticsChartStyle()
                    .frame(height: 150)
                    .accessibilityLabel("\(metric.title) over the last \(windowMinutes) minutes")
                    .accessibilityValue(latestDescription)
                    .accessibilityIdentifier("live-chart-\(metric.rawValue)")

                if metric == .power {
                    HStack(spacing: 14) {
                        ChartLegend("Drawing", color: TessalyticsTheme.warning)
                        ChartLegend("Regenerating", color: TessalyticsTheme.positive)
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart(points) { sample in
            if let value = metric.reading(of: sample) {
                marks(for: sample, value: value)
            }
        }
    }

    @ChartContentBuilder private func marks(for sample: LiveTelemetrySample, value: Double) -> some ChartContent {
        if metric == .power {
            BarMark(x: .value("Time", sample.date), y: .value(metric.title, value))
                .foregroundStyle(value < 0 ? TessalyticsTheme.positive : TessalyticsTheme.warning)
        } else {
            AreaMark(x: .value("Time", sample.date), y: .value(metric.title, value), stacking: .unstacked)
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(colors: [tint.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("Time", sample.date), y: .value(metric.title, value))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
        }
    }

    private var latestDescription: String {
        guard let value = points.last.flatMap({ metric.reading(of: $0) }) else { return "No readings" }
        return ValueFormatting.number(value, unit: unitSymbol, digits: metric == .batteryLevel ? 0 : 1)
    }
}
