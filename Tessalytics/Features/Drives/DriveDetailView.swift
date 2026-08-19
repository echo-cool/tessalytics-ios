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
                    VStack(spacing: 18) {
                    routeMap
                    addresses(detail)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Distance", value: ValueFormatting.number(detail.odometerDetails?.odometerDistance, unit: ""), symbol: "arrow.left.and.right")
                        MetricCard(title: "Duration", value: ValueFormatting.duration(minutes: detail.durationMin), symbol: "clock")
                        MetricCard(title: "Maximum speed", value: ValueFormatting.number(detail.speedMax, unit: ""), symbol: "speedometer")
                        MetricCard(title: "Energy", value: ValueFormatting.number(detail.energyConsumedNet, unit: "kWh"), symbol: "bolt")
                        MetricCard(title: "Ascent", value: ValueFormatting.number(elevationChange(detail).up, unit: "m"), symbol: "arrow.up.forward")
                        MetricCard(title: "Descent", value: ValueFormatting.number(elevationChange(detail).down, unit: "m"), symbol: "arrow.down.forward")
                        MetricCard(title: "Battery change", value: batteryChange(detail), symbol: "battery.50percent")
                        MetricCard(title: "Efficiency", value: ValueFormatting.number(detail.consumptionNet, unit: ""), symbol: "gauge.with.dots.needle.67percent")
                    }
                    chart(title: "Speed", unit: "", values: detail.driveDetails.compactMap { point in point.speed.map { (point.detailId, $0) } })
                    chart(title: "Power", unit: "kW", values: detail.driveDetails.compactMap { point in point.power.map { (point.detailId, $0) } })
                    chart(title: "Elevation", unit: "m", values: detail.driveDetails.compactMap { point in point.elevation.map { (point.detailId, $0) } })
                    chart(title: "Outside temperature", unit: "°", values: detail.driveDetails.compactMap { point in point.climateInfo?.outsideTemp.map { (point.detailId, $0) } })
                    ShareLink(item: summary(detail)) { Label("Share drive summary", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    EmptyState(title: "Route unavailable", message: errorMessage ?? "This drive could not be loaded.", symbol: "map")
                }
            }
        }
        .navigationTitle("Drive")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarLeading) { TessalyticsBackButton() }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { TessalyticsBackButton() }
            }
        }
        .task { await load() }
    }

    private var routeMap: some View {
        Map {
            if simplified.count > 1 { MapPolyline(coordinates: simplified.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(TessalyticsTheme.accent, lineWidth: 5) }
            if let first = simplified.first { Marker("Start", systemImage: "flag.fill", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)).tint(TessalyticsTheme.positive) }
            if let last = simplified.last { Marker("End", systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)).tint(TessalyticsTheme.critical) }
        }.mapStyle(.standard(elevation: .flat)).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityLabel("Drive route from start to end")
    }
    private func addresses(_ detail: DriveDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(detail.startAddress ?? "Start not reported", systemImage: "circle.fill")
            Label(detail.endAddress ?? "End not reported", systemImage: "mappin.circle.fill")
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    private func chart(title: String, unit: String, values: [(Int, Double)]) -> some View {
        SectionCard(title, symbol: "chart.xyaxis.line") {
            if values.isEmpty { Text("No samples reported").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100) }
            else {
                Chart(values, id: \.0) { value in
                    AreaMark(x: .value("Sample", value.0), y: .value(title, value.1))
                        .foregroundStyle(.linearGradient(colors: [TessalyticsTheme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Sample", value.0), y: .value(title, value.1))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.accent)
                }
                .chartXAxis(.hidden)
                .tessalyticsChartStyle()
                .frame(height: 180)
                .accessibilityLabel("\(title) chart with \(values.count) samples in \(unit)")
            }
        }
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
    private func summary(_ detail: DriveDetailDTO) -> String { "Drive from \(detail.startAddress ?? "an unreported location") to \(detail.endAddress ?? "an unreported location"). Distance: \(ValueFormatting.number(detail.odometerDetails?.odometerDistance, unit: "")). Duration: \(ValueFormatting.duration(minutes: detail.durationMin)). Generated by Tessalytics." }
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
}
