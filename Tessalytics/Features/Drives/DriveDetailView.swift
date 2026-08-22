import Charts
import MapKit
import SwiftData
import SwiftUI

struct DriveDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    let driveID: Int
    @State private var detail: DriveDetailDTO?
    @State private var simplified: [CoordinateDTO] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                if loading {
                    LoadingPanel(title: "Loading route", symbol: "map.fill")
                        .padding()
                } else if let detail {
                    VStack(spacing: TessalyticsLayout.stackSpacing) {
                    routeMap
                    addresses(detail)
                    MetricGrid {
                        MetricCard(
                            title: "Distance",
                            value: ValueFormatting.distance(detail.odometerDetails?.odometerDistance, units: environment.statusUnits),
                            symbol: "arrow.left.and.right",
                            detail: averageSpeedDetail(detail)
                        )
                        MetricCard(
                            title: "Duration",
                            value: ValueFormatting.duration(minutes: detail.durationMin),
                            symbol: "clock",
                            detail: ValueFormatting.date(detail.startDate?.value),
                            tint: TessalyticsTheme.neutral
                        )
                        MetricCard(
                            title: "Maximum speed",
                            value: ValueFormatting.speed(detail.speedMax, units: environment.statusUnits, digits: 0),
                            symbol: "speedometer",
                            detail: detail.speedAvg.map { "Avg \(ValueFormatting.speed($0, units: environment.statusUnits, digits: 0))" } ?? "Average not reported",
                            tint: TessalyticsTheme.warning
                        )
                        MetricCard(
                            title: "Energy used",
                            value: ValueFormatting.number(detail.energyConsumedNet, unit: "kWh"),
                            symbol: "bolt",
                            detail: ValueFormatting.efficiency(detail.consumptionNet, units: environment.statusUnits, digits: 0),
                            tint: TessalyticsTheme.positive
                        )
                        MetricCard(
                            title: "Battery used",
                            value: batteryChange(detail),
                            symbol: "battery.50percent",
                            detail: batteryEndpointsDetail(detail),
                            tint: TessalyticsTheme.positive
                        )
                        MetricCard(
                            title: "Elevation",
                            value: ValueFormatting.number(elevationChange(detail).up, unit: "m", digits: 0),
                            symbol: "arrow.up.forward",
                            detail: "-\(ValueFormatting.number(elevationChange(detail).down, unit: "m", digits: 0)) descent",
                            tint: TessalyticsTheme.neutral
                        )
                    }
                    chart(title: "Speed", unit: resolvedUnits.speedSymbol, values: series(detail) { $0.speed })
                    chart(title: "Power", unit: "kW", tint: TessalyticsTheme.warning, values: series(detail) { $0.power })
                    chart(title: "Battery level", unit: "%", tint: TessalyticsTheme.positive, values: series(detail) { $0.batteryLevel.map(Double.init) })
                    chart(title: "Elevation", unit: "m", tint: TessalyticsTheme.chartNeutral, baseline: .focused, values: series(detail) { $0.elevation })
                    chart(title: "Outside temperature", unit: resolvedUnits.temperatureSymbol, tint: TessalyticsTheme.steel, baseline: .focused, values: series(detail) { $0.climateInfo?.outsideTemp })
                    ShareLink(item: summary(detail)) { Label("Share drive summary", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                    .tessalyticsScreenPadding()
                    .tessalyticsReadableWidth(TessalyticsLayout.wideReadableWidth)
                } else {
                    EmptyState(title: "Route unavailable", message: errorMessage ?? "This drive could not be loaded.", symbol: "map")
                }
            }
        }
        .navigationTitle("Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var resolvedUnits: UnitsDTO { environment.statusUnits ?? .metricDefaults }


    private var routeMap: some View {
        Map {
            if simplified.count > 1 { MapPolyline(coordinates: simplified.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(TessalyticsTheme.accent, lineWidth: 5) }
            if let first = simplified.first { Marker("Start", systemImage: "flag.fill", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)).tint(TessalyticsTheme.positive) }
            if let last = simplified.last { Marker("End", systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)).tint(TessalyticsTheme.critical) }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 216)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityLabel("Drive route from start to end")
    }
    private func addresses(_ detail: DriveDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(detail.startAddress ?? "Start not reported", systemImage: "circle.fill")
            Label(detail.endAddress ?? "End not reported", systemImage: "mappin.circle.fill")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }
    /// Samples paired with the moment they were recorded.
    ///
    /// These charts used to plot against `detailId`, an opaque database row id,
    /// so the x-axis had to be hidden and the shape of the drive was unreadable.
    /// Plotting against time gives the axis real meaning.
    private func series(_ detail: DriveDetailDTO, _ value: (DrivePointDTO) -> Double?) -> [ChartSample] {
        detail.driveDetails.enumerated().compactMap { index, point in
            guard let date = point.date?.value, let measurement = value(point) else { return nil }
            return ChartSample(id: index, date: date, value: measurement)
        }
    }

    /// One of the drive's series.
    ///
    /// Tappable when there is anything to plot: the card shows the shape, and the
    /// screen behind it re-draws the same series, reads out any point under a
    /// finger, and lists the values as a table. A chart that cannot be
    /// interrogated leaves "what exactly happened at that dip" unanswerable.
    @ViewBuilder
    private func chart(
        title: String,
        unit: String,
        tint: Color = TessalyticsTheme.accent,
        baseline: ChartBaseline = .zero,
        values: [ChartSample]
    ) -> some View {
        if values.isEmpty {
            SectionCard(title, symbol: "chart.xyaxis.line", tint: tint) {
                Text("No samples reported")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        } else {
            NavigationSectionCard(
                title,
                subtitle: "Tap to read values · \(sampleCount(values))",
                symbol: "chart.xyaxis.line",
                tint: tint
            ) {
                ChartExplorerView(
                    chart: .timeSeries(title: title, unit: unit, tint: tint, baseline: baseline, samples: values)
                )
            } content: {
                plot(title: title, unit: unit, tint: tint, baseline: baseline, values: values)
            }
        }
    }

    private func sampleCount(_ values: [ChartSample]) -> String {
        "\(values.count.formatted()) sample\(values.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func plot(
        title: String,
        unit: String,
        tint: Color,
        baseline: ChartBaseline,
        values: [ChartSample]
    ) -> some View {
        Chart(downsampled(values)) { sample in
            if baseline == .zero {
                // Unstacked: AreaMark stacks by default, which for a dense single
                // series sums neighbouring samples and draws a trace several times
                // the real maximum.
                AreaMark(x: .value("Time", sample.date), y: .value(title, sample.value), stacking: .unstacked)
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
            }
            LineMark(x: .value("Time", sample.date), y: .value(title, sample.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
        }
        .chartValueDomain(baseline == .focused ? focusedChartDomain(for: values.map(\.value)) : nil)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.precision(.fractionLength(baseline == .focused ? 0...1 : 0...0))))
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .tessalyticsChartAxes(x: "Time of day", y: "\(title) (\(unit))")
        .tessalyticsChartStyle()
        .frame(height: 160)
        .accessibilityLabel("\(title) chart with \(values.count) samples in \(unit)")

        ChartLegend("\(title) (\(unit))", color: tint)
    }

    private func load() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        defer { loading = false }
        do {
            let loaded = try await DriveRepository(context: context).detail(client: environment.client(for: profile), serverID: profile.id, carID: vehicle.id, driveID: driveID)
            try Task.checkCancellation()
            detail = loaded
            let coordinates = loaded.driveDetails.map(\.coordinate)
            let simplificationTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let route = RouteSimplifier.simplify(coordinates)
                try Task.checkCancellation()
                return route
            }
            simplified = try await withTaskCancellationHandler {
                try await simplificationTask.value
            } onCancel: {
                simplificationTask.cancel()
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    private func summary(_ detail: DriveDetailDTO) -> String { "Drive from \(detail.startAddress ?? "an unreported location") to \(detail.endAddress ?? "an unreported location"). Distance: \(ValueFormatting.distance(detail.odometerDetails?.odometerDistance, units: environment.statusUnits)). Duration: \(ValueFormatting.duration(minutes: detail.durationMin)). Generated by Tessalytics." }
    private func elevationChange(_ detail: DriveDetailDTO) -> (up: Double?, down: Double?) {
        let elevations = detail.driveDetails.compactMap(\.elevation)
        guard elevations.count > 1 else { return (nil, nil) }
        var up = 0.0, down = 0.0
        for pair in zip(elevations, elevations.dropFirst()) { let delta = pair.1 - pair.0; if delta > 0 { up += delta } else { down -= delta } }
        return (up, down)
    }
    private func batteryChange(_ detail: DriveDetailDTO) -> String {
        let levels = detail.driveDetails.compactMap(\.batteryLevel)
        guard let first = levels.first, let last = levels.last else { return "Unavailable" }
        return "\(last - first)%"
    }

    /// Average speed derived from distance and duration — the API reports an
    /// average, but this covers the sessions where it does not.
    private func averageSpeedDetail(_ detail: DriveDetailDTO) -> String {
        guard let distance = detail.odometerDetails?.odometerDistance,
              let minutes = detail.durationMin, minutes > 0 else { return "Distance travelled" }
        let perHour = distance / (Double(minutes) / 60)
        return "Avg \(ValueFormatting.speed(perHour, units: environment.statusUnits, digits: 0))"
    }

    private func batteryEndpointsDetail(_ detail: DriveDetailDTO) -> String {
        let levels = detail.driveDetails.compactMap(\.batteryLevel)
        guard let first = levels.first, let last = levels.last else { return "Not reported" }
        return "\(first)% → \(last)%"
    }
}
