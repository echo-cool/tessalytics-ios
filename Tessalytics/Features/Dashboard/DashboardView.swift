import Charts
import MapKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var recentDrives: [DriveRecord] = []
    @State private var recentCharges: [ChargeRecord] = []
    @State private var capacityObservations: [CapacityObservation] = []
    @State private var capacityMedians: [CapacityObservation] = []
    @State private var visitedPlaces: [VisitedPlace] = []
    @State private var visitedSegments: [[CoordinateDTO]] = []
    @State private var batteryLevels: [BatteryLevelPoint] = []
    /// Kept out of the way once read: it is a first-week explanation, not a
    /// standing warning.
    @AppStorage("dismissedHistoryNotice") private var dismissedHistoryNotice = false
    @State private var isShowingLiveMap = false
    /// The QR sheet that signs a browser in to the web dashboard.
    @State private var isShowingPairing = false
    /// Which of the hero card's destinations is open, if any.
    @State private var heroDestination: VehicleHeroDestination?
    @State private var heroSnapshot = RoutePosterSnapshot()
    @State private var placesSnapshot = RoutePosterSnapshot()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isRenderingSharePoster) private var isRenderingPoster

    var body: some View {
        NavigationStack {
            TessalyticsScreen(isLive: environment.isLiveDriving) {
                if environment.vehicles.isEmpty {
                    EmptyState(
                        title: "No vehicles",
                        message: "No synchronized vehicles are available for this server.",
                        symbol: "car.slash"
                    )
                } else {
                    dashboardContent
                }
            }
            // The app's name, not the car's. The hero card names the car
            // directly beneath this, and the vehicle picker in the toolbar names
            // it again — three times over, with a long name truncating to nothing
            // useful in the one place that cannot show the rest.
            .navigationTitle("Tessalytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Top left, where a car's screen sends people looking for it: the
                // dashboard shows a code and this is the thing that reads it.
                ToolbarItem(placement: .topBarLeading) { pairingButton }
                ToolbarItem(placement: .topBarTrailing) { vehicleMenu }
            }
            .safeAreaInset(edge: .top) { statusBanner }
            .shareablePage(sharePage, prepare: prepareMapSnapshots) {
                VStack(spacing: TessalyticsLayout.stackSpacing) { dashboardPoster }
            }
            .fullScreenCover(isPresented: $isShowingLiveMap) { LiveMapScreen() }
            .sheet(isPresented: $isShowingPairing) { WebPairingSheet() }
            // Keyed on the vehicle so this also fires the first time a vehicle
            // becomes known — right after a server is configured, for instance.
            .task(id: environment.selectedVehicle?.id) {
                loadCachedHistory()
                if scenePhase == .active { environment.handleForegroundEntry() }
                // Always ask the server on open. Relying on the poll timer meant
                // the screen could open showing a stale "latest drive".
                await refreshRecentDrives()
            }
            // History syncs replace the cached rows underneath this screen.
            .task(id: environment.historyRevision) { loadCachedHistory() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    environment.handleForegroundEntry()
                case .background:
                    environment.handleBackgroundEntry()
                case .inactive:
                    // Not backgrounded. A notification banner, the app switcher,
                    // Control Center and the screen dimming all pass through
                    // `.inactive` with the app still on screen — and tearing the
                    // stream down for each of them left a drive reconnecting
                    // fifteen times in half an hour, running on the poll in
                    // between.
                    break
                @unknown default:
                    break
                }
            }
        }
        .accessibilityIdentifier("dashboard-screen")
    }

    /// Opens the scanner that signs a browser in to the web dashboard.
    ///
    /// Deliberately a single tap from the first screen rather than buried in
    /// Settings: it is used while sitting in the car with the dashboard already
    /// open on the centre screen, waiting on a code that expires in three minutes.
    private var pairingButton: some View {
        Button {
            isShowingPairing = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
        }
        .accessibilityLabel("Sign in a browser")
        .accessibilityIdentifier("scan-pairing-code")
    }

    /// The map is presented full screen; everything else is a push.
    private func open(_ destination: VehicleHeroDestination) {
        if destination == .map {
            isShowingLiveMap = true
        } else {
            heroDestination = destination
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if environment.isDemoMode {
            DemoModeBanner()
        } else if environment.isOffline {
            OfflineBanner()
        }
    }

    /// Pull to refresh must await the work it started.
    ///
    /// The previous version fired two detached tasks and then slept 350 ms, so the
    /// control reported completion before any data had arrived. It also attached
    /// `.refreshable` to this screen's outermost content rather than to the scroll
    /// view itself, leaving SwiftUI to locate the scroll view through a `ZStack`
    /// and a conditional branch; the control is now attached directly to the
    /// `ScrollView` that owns it.
    private func refreshAll() async {
        await environment.refreshStatus()
        await environment.refreshHistory()
        await refreshRecentDrives()
        loadCachedHistory()
    }

    private func loadCachedCharges() -> [ChargeRecord] {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return [] }
        return ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
    }


    /// What goes in a shared picture of the home screen.
    ///
    /// Not the whole screen: the quick links are buttons, the pairing notice is a
    /// prompt to this phone's owner, and the Tesla controls card is a set of
    /// switches. None of them mean anything as a picture.
    @ViewBuilder private var dashboardPoster: some View {
        VehicleHeroCard(
            posterMap: heroSnapshot.image,
            vehicle: environment.selectedVehicle,
            status: environment.status,
            units: environment.statusUnits,
            freshnessLabel: freshnessLabel,
            freshnessColor: freshnessColor,
            updatedAt: environment.statusFetchedAt,
            battery: environment.fleet.battery,
            activity: recentDrivePoints,
            efficiency: recentEfficiency,
            batteryLevels: batteryLevels,
            tyres: environment.status?.tpmsDetails?.hasAnyReading == true
                ? environment.status?.tpmsDetails
                : environment.lastLiveStatus?.tpmsDetails,
            route: environment.liveMapRoute,
            liveTotals: environment.liveDriveTotals,
            isStreaming: environment.isStreamingLive,
            isDriving: environment.isLiveDriving,
            coordinate: environment.liveCoordinate ?? environment.status?.carGeodata?.location,
            placeName: environment.livePlace.name,
            onOpen: { _ in }
        )
        if !visitedPlaces.isEmpty {
            SectionCard("Places", subtitle: placesSubtitle, symbol: "map.fill", tint: TessalyticsTheme.neutral) {
                RoutePosterMap(height: 190, snapshot: placesSnapshot.image)
            }
        }
    }

    private func prepareMapSnapshots() async {
        let width = SharePoster<AnyView>.width - 64
        if let coordinate = environment.liveCoordinate ?? environment.status?.carGeodata?.location {
            let trail = environment.liveMapRoute.coordinates
            await heroSnapshot.load(
                segments: trail.count > 1 ? [trail] : [],
                pins: [CoordinateDTO(latitude: coordinate.latitude, longitude: coordinate.longitude)],
                size: CGSize(width: width, height: 128),
                colorScheme: colorScheme
            )
        }
        if !visitedPlaces.isEmpty {
            await placesSnapshot.load(
                segments: visitedSegments,
                pins: visitedPlaces.map { CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude) },
                size: CGSize(width: width, height: 190),
                colorScheme: colorScheme
            )
        }
    }

    private func sharePage() -> SharePage {
        let units = environment.statusUnits
        let status = environment.status
        var highlights: [ShareHighlight] = []
        if let level = status?.batteryDetails?.batteryLevel {
            highlights.append(.init(label: "battery", value: "\(level)%"))
        }
        if let range = status?.batteryDetails?.ratedBatteryRange {
            highlights.append(.init(label: "range", value: ValueFormatting.distance(range, units: units, digits: 2)))
        }
        if let odometer = status?.odometer {
            highlights.append(.init(label: "odometer", value: ValueFormatting.distance(odometer, units: units, digits: 1)))
        }

        var sentences: [String] = []
        let car = environment.selectedVehicle?.name?.nilIfEmpty ?? "My Tesla"
        if let level = status?.batteryDetails?.batteryLevel {
            var line = "\(car) is at \(level)%"
            if let range = status?.batteryDetails?.ratedBatteryRange {
                line += ", \(ValueFormatting.distance(range, units: units, digits: 2)) of rated range"
            }
            sentences.append(line + ".")
        }
        if let place = environment.livePlace.name?.nilIfEmpty {
            sentences.append(environment.isLiveDriving ? "Near \(place)." : "Parked at \(place).")
        }
        sentences.append("From Tessalytics.")
        return SharePage(
            title: car,
            subtitle: SharePage.subtitle(car: environment.selectedVehicle?.name),
            highlights: highlights,
            summary: sentences.joined(separator: " ")
        )
    }

    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                VehicleHeroCard(
                    posterMap: heroSnapshot.image,
                    vehicle: environment.selectedVehicle,
                    status: environment.status,
                    units: environment.statusUnits,
                    freshnessLabel: freshnessLabel,
                    freshnessColor: freshnessColor,
                    updatedAt: environment.statusFetchedAt,
                    battery: environment.fleet.battery,
                    activity: recentDrivePoints,
                    efficiency: recentEfficiency,
                    batteryLevels: batteryLevels,
                    // A sleeping car reports 0 psi at every corner, so fall
                    // back to the last reading taken while it was awake.
                    tyres: environment.status?.tpmsDetails?.hasAnyReading == true
                        ? environment.status?.tpmsDetails
                        : environment.lastLiveStatus?.tpmsDetails,
                    route: environment.liveMapRoute,
                    liveTotals: environment.liveDriveTotals,
                    isStreaming: environment.isStreamingLive,
                    isDriving: environment.isLiveDriving,
                    coordinate: environment.liveCoordinate ?? environment.status?.carGeodata?.location,
                    placeName: environment.livePlace.name,
                    onOpen: open
                )
                .navigationDestination(item: $heroDestination) { destination in
                    switch destination {
                    case .batteryHealth: BatteryHealthView()
                    case .drives: DriveHistoryView()
                    case .tyres: TyrePressureView()
                    case .vehicle: VehicleSettingsView()
                    // The map is a cover rather than a push, and is handled
                    // before it ever reaches here.
                    case .map: EmptyView()
                    }
                }

                historyNotice

                DashboardQuickLinks()

                // Behind the debug unlock — see the note in SettingsView.
                if environment.diagnostics.isUnlocked,
                   environment.hasOwnerCredentials,
                   environment.isOwnerConnected {
                    DirectTeslaControlsCard()
                }

                // Parked: somewhere to go. Driving: what the car is doing. The two
                // are never both useful at once.
                if !environment.isLiveDriving, !visitedPlaces.isEmpty {
                    DestinationsCard(places: visitedPlaces)
                }

                if environment.isLiveDriving {
                    LiveDriveSection(
                        buffer: environment.liveTelemetry,
                        totals: environment.liveDriveTotals,
                        units: environment.statusUnits
                    )
                }

                // Capacity against mileage, in place of the five-figure strip
                // that used to sit in the hero card.
                NavigationSectionCard(
                    "Battery capacity",
                    subtitle: capacitySubtitle,
                    symbol: "battery.100percent",
                    tint: TessalyticsTheme.positive
                ) {
                    ChartExplorerView(chart: capacityExplorable)
                } content: {
                    CapacityByMileageChart(
                        observations: capacityObservations,
                        medians: capacityMedians,
                        capacityNew: environment.fleet.battery?.capacityNew,
                        units: environment.statusUnits,
                        showsHeader: false
                    )
                }

                NavigationSectionCard(
                    "Places",
                    subtitle: placesSubtitle,
                    symbol: "map.fill",
                    tint: TessalyticsTheme.neutral
                ) {
                    VisitedPlacesScreen()
                } content: {
                    if visitedPlaces.isEmpty {
                        ChartNeedsMoreHistory(
                            needs: "one synced drive with coordinates",
                            symbol: "map"
                        )
                    } else {
                        if isRenderingPoster {
                            RoutePosterMap(height: 190, snapshot: placesSnapshot.image)
                        } else {
                            VisitedPlacesMap(places: visitedPlaces, segments: visitedSegments)
                                .frame(height: 190)
                                .clipShape(.rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous))
                                .allowsHitTesting(false)
                        }
                    }
                }

                if let status = environment.status {
                    NavigationSectionCard(
                        "Recent driving",
                        subtitle: "7 days · \(ValueFormatting.distance(weeklyDistance, units: environment.statusUnits, digits: 0))",
                        symbol: "chart.bar.fill",
                        tint: TessalyticsTheme.accent
                    ) {
                        ChartExplorerView(chart: recentDrivingExplorable)
                    } content: {
                        RecentDrivingChart(points: recentDrivePoints, units: environment.statusUnits)
                    }

                    VehicleTelemetryGrid(
                        status: status,
                        units: environment.statusUnits,
                        history: history
                    )

                    if let latest = recentDrives.first {
                        LatestDriveCard(record: latest)
                    }

                    DriveStatsCard(stats: environment.fleet.drives, units: environment.statusUnits, isComplete: environment.fleet.isComplete)
                    ChargingSummaryCard(
                        stats: environment.fleet.charging,
                        capacityNew: environment.fleet.battery?.capacityNew,
                        isComplete: environment.fleet.isComplete
                    )
                    ChargingStatusCard(status: status)
                    VehicleSecurityCard(
                        status: status,
                        lastLive: environment.lastLiveStatus,
                        lastLiveAt: environment.lastLiveStatusAt
                    )
                    TirePressureCard(status: status, units: environment.statusUnits)
                    VehicleActivityCard(vehicle: environment.selectedVehicle, weeklyDrives: history.weeklyDrives)
                    VehicleDetailsCard(status: status, placeName: environment.livePlace.name)
                } else {
                    StatusRefreshCard(
                        isRefreshing: environment.isStatusRefreshing,
                        message: environment.lastError
                    ) {
                        environment.requestStatusRefresh()
                    }
                }
            }
            .tessalyticsScreenPadding()
            .tessalyticsReadableWidth()
        }
        .refreshable { await refreshAll() }
    }

    /// Distance covered over the seven days the chart above shows, so the
    /// odometer tile can say how much of it is recent.
    private var weeklyDistance: Double { recentDrivePoints.map(\.distance).reduce(0, +) }

    private var recentDrivePoints: [RecentDrivePoint] {
        if environment.isDemoMode {
            let calendar = Calendar.current
            let values = [12.4, 0, 28.7, 8.2, 41.5, 16.8, 23.1]
            return values.enumerated().map { index, value in
                RecentDrivePoint(
                    date: calendar.date(byAdding: .day, value: index - 6, to: calendar.startOfDay(for: .now)) ?? .now,
                    distance: value
                )
            }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let grouped = Dictionary(grouping: recentDrives) { record in
            calendar.startOfDay(for: record.startDate ?? .distantPast)
        }
        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return RecentDrivePoint(
                date: date,
                distance: grouped[date, default: []].compactMap(\.distance).reduce(0, +)
            )
        }
    }

    private func loadCachedHistory() {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            recentDrives = []
            recentCharges = []
            capacityObservations = []
            capacityMedians = []
            visitedPlaces = []
            visitedSegments = []
            batteryLevels = []
            return
        }
        recentDrives = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        recentCharges = loadCachedCharges()

        capacityObservations = CapacityModel.observations(
            charges: recentCharges,
            ratedEfficiency: environment.fleet.battery?.ratedEfficiency,
            units: environment.statusUnits
        )
        capacityMedians = CapacityModel.semiMonthlyMedians(capacityObservations)

        visitedPlaces = VisitedPlacesModel.places(from: recentDrives.flatMap(\.visitedEndpoints))
        visitedSegments = cachedTrackSegments(serverID: profile.id, carID: vehicle.id, context: context)
        batteryLevels = BatteryLevelHistory.points(
            drives: recentDrives,
            charges: recentCharges,
            since: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast,
            currentLevel: environment.status?.batteryDetails?.batteryLevel
        )
    }

    private var capacitySubtitle: String {
        guard let battery = environment.fleet.battery, let health = battery.healthPercent else {
            return "Modeled per charge"
        }
        return "\(ValueFormatting.percentage(health / 100, digits: 1)) of as-new"
    }

    /// Median consumption over the last thirty days of drives.
    ///
    /// A median rather than a mean: one short cold-start trip can carry a
    /// consumption several times the normal figure and would drag an average with
    /// it, which is exactly the number an owner would then distrust.
    private var recentEfficiency: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let values = recentDrives
            .filter { ($0.startDate ?? .distantPast) >= cutoff }
            .compactMap(\.efficiency)
            .filter { $0 > 0 }
            .sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    /// Shown while TeslaMate has barely any history for this car.
    ///
    /// Half of this app is derived from weeks of recorded drives and charges, and
    /// on a fresh install almost none of it can be computed. Without saying so,
    /// the first impression is a screen of blank panels that reads as broken
    /// rather than as new — and the fix, waiting, is not one anybody guesses.
    @ViewBuilder private var historyNotice: some View {
        if let span = historySpan, !dismissedHistoryNotice, !environment.isDemoMode {
            SurfaceCard(tint: TessalyticsTheme.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Still collecting history", systemImage: "hourglass")
                        .font(.subheadline.weight(.semibold))
                    Text(span)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Capacity, projected range and the trend charts need a week or two of driving and charging before they mean anything. They fill in on their own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Got it") { dismissedHistoryNotice = true }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("history-notice")
        }
    }

    private var historySpan: String? {
        HistoryCoverage.summary(of: recentDrives.compactMap(\.startDate) + recentCharges.compactMap(\.startDate))
    }

    private var placesSubtitle: String {
        visitedPlaces.isEmpty ? "No coordinates yet" : "\(visitedPlaces.count) visited"
    }

    private var recentDrivingExplorable: ExplorableChart {
        let unit = (environment.statusUnits ?? .metricDefaults).lengthSymbol
        return ExplorableChart(
            title: "Recent driving",
            subtitle: "Distance per day, last 7 days",
            xLabel: "Day",
            yLabel: "Distance (\(unit))",
            unit: unit,
            fractionDigits: 1,
            points: recentDrivePoints.enumerated().map { index, point in
                ExplorableChartPoint(
                    id: index,
                    label: point.date.formatted(.dateTime.weekday(.abbreviated)),
                    detail: point.date.formatted(date: .abbreviated, time: .omitted),
                    value: point.distance
                )
            },
            styles: [.bar, .line, .area, .pie],
            tint: TessalyticsTheme.accent
        )
    }

    /// Capacity against mileage, so a scrub reads out the odometer it belongs to.
    ///
    /// Drawn the same way as the card it is opened from: the faint per-charge
    /// scatter, the semi-monthly median through it, and the as-new line above
    /// both. A detail screen that redraws the same numbers in a different form
    /// makes the reader work out whether they are even looking at the same thing.
    private var capacityExplorable: ExplorableChart {
        let unit = (environment.statusUnits ?? .metricDefaults).lengthSymbol
        let odometers = capacityObservations.map(\.odometer)
        return ExplorableChart(
            title: "Battery capacity",
            subtitle: "Modeled per charge, by odometer",
            xLabel: "Odometer (\(unit))",
            yLabel: "Usable capacity (kWh)",
            unit: "kWh",
            fractionDigits: 2,
            points: capacityObservations.enumerated().map { index, observation in
                ExplorableChartPoint(
                    id: index,
                    // Tenths of a thousand: plain compact notation rounds 15,800
                    // and 16,400 both to "16K" and the axis repeats itself.
                    label: "\((observation.odometer / 1_000).formatted(.number.precision(.fractionLength(1))))K",
                    detail: "\(observation.odometer.formatted(.number.precision(.fractionLength(0)))) \(unit)",
                    value: observation.capacity
                )
            },
            // The medians carry their own odometers, which are not the odometers
            // of the charges, so they are placed between the readings they sit
            // between rather than against an index of their own.
            trend: ExplorableTrendPoint.positioned(
                capacityMedians.map { (x: $0.odometer, y: $0.capacity) },
                onto: odometers
            ),
            pointsLabel: "Per charge",
            trendLabel: "Semi-monthly median",
            reference: environment.fleet.battery?.capacityNew.map {
                ExplorableReference(value: $0, label: "When new")
            },
            // Points first, as the card draws it. A pack size is not a share of
            // anything, so no pie here.
            styles: [.scatter, .line, .area, .bar],
            tint: TessalyticsTheme.positive,
            baseline: .focused,
            isCumulative: false
        )
    }

    /// Synchronized history is the one thing that stays true when the car is
    /// asleep, so the dashboard leans on it whenever live telemetry is stale.
    private var history: DashboardHistorySummary {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let lastDrive = recentDrives.first
        let lastCharge = recentCharges.first
        return DashboardHistorySummary(
            lastDriveDistance: lastDrive?.distance,
            lastDriveDate: lastDrive?.startDate,
            lastDriveDurationMinutes: lastDrive?.durationMinutes,
            weeklyDistance: weeklyDistance,
            weeklyDrives: environment.isDemoMode
                ? 6
                : recentDrives.filter { ($0.startDate ?? .distantPast) >= cutoff }.count,
            lastChargeEnergy: lastCharge?.energyAdded,
            lastChargeDate: lastCharge?.startDate
        )
    }

    private func refreshRecentDrives() async {
        guard !environment.isDemoMode,
              let profile = environment.selectedProfile,
              let vehicle = environment.selectedVehicle else { return }
        do {
            recentDrives = try await DriveRepository(context: context).refresh(
                client: environment.client(for: profile),
                serverID: profile.id,
                carID: vehicle.id,
                page: 1,
                filter: .init()
            )
        } catch {
            recentDrives = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        }
        recentCharges = loadCachedCharges()
    }

    private var freshnessLabel: String? {
        if environment.isDemoMode && !environment.statusUsesOwnerAPI { return "Demo" }
        if environment.isOffline { return "Stale" }
        if environment.statusUsesOwnerAPI { return "Direct live" }
        guard let fetched = environment.statusFetchedAt else { return "Connecting" }
        if Date().timeIntervalSince(fetched) > 120 { return "Stale" }
        // Nothing to say: the data is current, and whether the car happens to be
        // awake is the card's job to show, not a chip's.
        return environment.status?.state == "online" ? "Live" : nil
    }

    private var freshnessColor: Color {
        if environment.isDemoMode && !environment.statusUsesOwnerAPI { return TessalyticsTheme.accent }
        return environment.isOffline ? TessalyticsTheme.warning : environment.status?.state == "online" ? TessalyticsTheme.positive : TessalyticsTheme.steel
    }

    private var vehicleMenu: some View {
        Menu {
            ForEach(environment.vehicles) { vehicle in
                Button {
                    environment.selectVehicle(vehicle)
                } label: {
                    if environment.selectedVehicle?.id == vehicle.id {
                        Label(vehicle.name ?? "Vehicle \(vehicle.id)", systemImage: "checkmark")
                    } else {
                        Text(vehicle.name ?? "Vehicle \(vehicle.id)")
                    }
                }
            }
        } label: {
            Label("Choose vehicle", systemImage: "car.2.fill")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Choose vehicle")
    }
}

/// Vehicle metric tiles.
///
/// Every tile carries a detail line so row heights and value baselines stay
/// identical across the grid. The second half of the grid swaps between live
/// telemetry and synchronized history depending on whether the car was awake at
/// the last poll — a sleeping car reports no cabin temperature or charge limit,
/// so those tiles would be pure noise.
private struct VehicleTelemetryGrid: View {
    let status: VehicleStatus
    let units: UnitsDTO?
    let history: DashboardHistorySummary

    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }
    private var isLive: Bool { status.reportsLiveTelemetry }

    var body: some View {
        MetricGrid {
            MetricCard(
                title: "Odometer",
                value: ValueFormatting.distance(status.odometer, units: units, digits: 0),
                symbol: "gauge.open.with.lines.needle.33percent",
                detail: history.weeklyDistance > 0
                    ? "+\(ValueFormatting.distance(history.weeklyDistance, units: units, digits: 0)) / 7 days"
                    : "No drives in 7 days",
                tint: TessalyticsTheme.neutral
            )
            MetricCard(
                title: "Range",
                value: status.batteryDetails?.displayRange.map {
                    ValueFormatting.distance($0.value, units: units, digits: 0)
                } ?? "Unavailable",
                symbol: "road.lanes",
                detail: rangeKindDetail,
                tint: TessalyticsTheme.accent
            )
            MetricCard(
                title: "Usable charge",
                value: percentage(status.batteryDetails?.usableBatteryLevel),
                symbol: "battery.75percent",
                detail: usableChargeDetail,
                tint: TessalyticsTheme.positive
            )

            if isLive {
                MetricCard(
                    title: "Charge limit",
                    value: percentage(status.chargingDetails?.reportedChargeLimit),
                    symbol: "bolt.badge.checkmark",
                    detail: chargeLimitDetail,
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Cabin",
                    value: ValueFormatting.temperature(status.climateDetails?.insideTemp, units: units, digits: 1),
                    symbol: "thermometer.medium",
                    detail: status.climateDetails?.isPreconditioning == true
                        ? "Preconditioning"
                        : (status.climateDetails?.isClimateOn == true ? "Climate on" : "Climate off"),
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Outside",
                    value: ValueFormatting.temperature(status.climateDetails?.outsideTemp, units: units, digits: 1),
                    symbol: "thermometer.sun",
                    detail: cabinDeltaDetail,
                    tint: TessalyticsTheme.warning
                )
                // The server reports this and the app used to discard it. It is
                // the difference between a car parked with someone in it and one
                // parked alone with the sentry watching.
                if let occupied = status.drivingDetails?.isUserPresent {
                    MetricCard(
                        title: "Occupancy",
                        value: occupied ? "Someone aboard" : "Empty",
                        symbol: occupied ? "figure.seated.side.right" : "car.side",
                        detail: occupied ? "The car reports a driver" : "Nobody in the car",
                        tint: occupied ? TessalyticsTheme.accent : TessalyticsTheme.neutral
                    )
                    .accessibilityIdentifier("vehicle-occupancy")
                }
            } else {
                MetricCard(
                    title: "Last drive",
                    value: history.lastDriveDistance.map {
                        ValueFormatting.distance($0, units: units, digits: 1)
                    } ?? "No drives",
                    symbol: "car.side.fill",
                    detail: lastDriveDetail,
                    tint: TessalyticsTheme.accent
                )
                MetricCard(
                    title: "Drives this week",
                    value: history.weeklyDrives.formatted(),
                    symbol: "calendar",
                    detail: weeklyAverageDetail,
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Last charge",
                    value: history.lastChargeEnergy.map {
                        ValueFormatting.number($0, unit: "kWh")
                    } ?? "No charges",
                    symbol: "bolt.fill",
                    detail: lastChargeDetail,
                    tint: TessalyticsTheme.positive
                )
            }
        }
    }

    private func percentage(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "Unavailable"
    }

    /// Names which of TeslaMate's three range figures is on screen.
    private var rangeKindDetail: String {
        guard let range = status.batteryDetails?.displayRange else { return "Not reported" }
        return range.label.capitalizedFirst
    }

    /// The cold-weather buffer, preferring the server's own figure.
    ///
    /// Subtracting the two levels here needs both of them to have arrived; the
    /// server computes it from whatever it has, so it can answer when this
    /// cannot.
    private var usableChargeDetail: String {
        if let buffer = status.batteryDetails?.bufferLevel, buffer > 0 { return "\(buffer) pt cold buffer" }
        guard let displayed = status.batteryDetails?.batteryLevel else { return "Usable capacity" }
        guard let usable = status.batteryDetails?.usableBatteryLevel else { return "Displayed \(displayed)%" }
        let difference = displayed - usable
        return difference > 0 ? "\(difference) pt cold buffer" : "Displayed \(displayed)%"
    }

    private var chargeLimitDetail: String {
        guard let limit = status.chargingDetails?.reportedChargeLimit else { return "Not reported" }
        guard let level = status.batteryDetails?.batteryLevel else { return "Target charge" }
        let remaining = limit - level
        if remaining > 0 { return "\(remaining) pts to target" }
        return remaining == 0 ? "At target" : "\(-remaining) pts above"
    }

    private var cabinDeltaDetail: String {
        guard let inside = status.climateDetails?.insideTemp,
              let outside = status.climateDetails?.outsideTemp else { return "Ambient" }
        let delta = inside - outside
        guard abs(delta) >= 0.5 else { return "Level with cabin" }
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(0)))
        return "Cabin \(delta > 0 ? "+" : "-")\(magnitude)\(resolvedUnits.temperatureSymbol)"
    }

    private var lastDriveDetail: String {
        guard let date = history.lastDriveDate else { return "Nothing synced yet" }
        guard let minutes = history.lastDriveDurationMinutes else {
            return date.formatted(.relative(presentation: .named))
        }
        return "\(ValueFormatting.duration(minutes: minutes)) · \(date.formatted(.relative(presentation: .named)))"
    }

    private var weeklyAverageDetail: String {
        guard history.weeklyDrives > 0 else { return "Last 7 days" }
        let average = history.weeklyDistance / Double(history.weeklyDrives)
        return "\(ValueFormatting.distance(average, units: units, digits: 1)) average"
    }

    private var lastChargeDetail: String {
        guard let date = history.lastChargeDate else { return "Nothing synced yet" }
        return date.formatted(.relative(presentation: .named))
    }
}

/// Battery health inside the hero card.
///
/// Five figures, in the order the pack degrades: what it held when new, what it
/// holds now, the range that implies at each point, and the difference.
private struct MiniStat: View {
    let title: String
    let value: String
    var tint: Color = .primary

    init(_ title: String, _ value: String, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Logged distance against what the odometer actually moved.
private struct DriveStatsCard: View {
    let stats: FleetStatistics.DriveStats
    let units: UnitsDTO?
    let isComplete: Bool

    var body: some View {
        NavigationSectionCard(
            "Drive stats",
            subtitle: isComplete
                ? "Every synchronized drive · \(stats.driveCount.formatted()) recorded"
                : "Syncing history — totals still incomplete",
            symbol: "road.lanes",
            tint: TessalyticsTheme.accent
        ) {
            DriveHistoryView(embedded: true, title: "Drives")
        } content: {
            MetricGrid {
                MetricCard(
                    title: "Logged miles",
                    value: ValueFormatting.distance(stats.loggedDistance, units: units, digits: 0),
                    symbol: "checkmark.circle.fill",
                    detail: "\(stats.driveCount.formatted()) drives",
                    tint: TessalyticsTheme.accent
                )
                MetricCard(
                    title: "Odometer",
                    value: ValueFormatting.distance(stats.odometer, units: units, digits: 0),
                    symbol: "gauge.open.with.lines.needle.33percent",
                    detail: stats.firstLoggedOdometer.map {
                        "Logging from \(ValueFormatting.distance($0, units: units, digits: 0))"
                    } ?? "Reported by the vehicle",
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Data lost",
                    value: stats.unloggedDistance.map {
                        ValueFormatting.distance($0, units: units, digits: 0)
                    } ?? "Unavailable",
                    symbol: "exclamationmark.triangle.fill",
                    // Distance the odometer moved that never reached the database:
                    // drives during logger downtime, sleep-detection gaps, or a
                    // paused logger.
                    detail: stats.coverage.map { "\(ValueFormatting.percentage($0, digits: 1)) captured" }
                        ?? "Needs an odometer reading",
                    tint: TessalyticsTheme.warning
                )
            }
        }
    }
}

/// Lifetime charging totals.
private struct ChargingSummaryCard: View {
    let stats: FleetStatistics.ChargingStats
    let capacityNew: Double?
    let isComplete: Bool

    var body: some View {
        NavigationSectionCard(
            "Charging totals",
            subtitle: isComplete
                ? "Every synchronized session"
                : "Syncing history — totals still incomplete",
            symbol: "bolt.batteryblock.fill",
            tint: TessalyticsTheme.positive
        ) {
            ChargeHistoryView(embedded: true, title: "Charging")
        } content: {
            MetricGrid {
                MetricCard(
                    title: "Charges",
                    value: stats.chargeCount.formatted(),
                    symbol: "bolt.car.fill",
                    detail: cyclesDetail,
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Charging cycles",
                    value: stats.cycles(capacityNew: capacityNew).map {
                        $0.formatted(.number.precision(.fractionLength(1)))
                    } ?? "Unavailable",
                    symbol: "arrow.triangle.2.circlepath",
                    // Equivalent full charges, not a count of plug-ins.
                    detail: capacityNew.map {
                        "Per \(ValueFormatting.number($0, unit: "kWh")) pack"
                    } ?? "Needs pack capacity",
                    tint: TessalyticsTheme.neutral
                )
                MetricCard(
                    title: "Energy added",
                    value: ValueFormatting.energy(stats.energyAdded),
                    symbol: "battery.100percent.bolt",
                    detail: "Reached the pack",
                    tint: TessalyticsTheme.positive
                )
                MetricCard(
                    title: "Energy used",
                    value: ValueFormatting.energy(stats.energyUsed),
                    symbol: "powerplug.fill",
                    detail: "Drawn from the outlet",
                    tint: TessalyticsTheme.steel
                )
                MetricCard(
                    title: "Charging efficiency",
                    value: ValueFormatting.percentage(stats.efficiency, digits: 1),
                    symbol: "gauge.with.dots.needle.67percent",
                    detail: lossDetail,
                    tint: TessalyticsTheme.warning
                )
                MetricCard(
                    title: "Total cost",
                    value: ValueFormatting.chargeCost(stats.costTotal),
                    symbol: "creditcard.fill",
                    detail: stats.pricedChargeCount > 0
                        ? "\(stats.pricedChargeCount.formatted()) of \(stats.chargeCount.formatted()) priced"
                        : "No tariff configured",
                    tint: TessalyticsTheme.steel
                )
            }
        }
    }

    private var cyclesDetail: String {
        guard stats.chargeCount > 0, stats.energyAdded > 0 else { return "Nothing synced yet" }
        let average = stats.energyAdded / Double(stats.chargeCount)
        return "\(ValueFormatting.number(average, unit: "kWh")) average"
    }

    private var lossDetail: String {
        guard let efficiency = stats.efficiency else { return "Needs drawn energy" }
        let lost = stats.energyUsed - stats.energyAdded
        guard lost > 0 else { return "No measurable loss" }
        _ = efficiency
        return "\(ValueFormatting.energy(lost)) lost"
    }
}

/// Shortcut row to the screens the dashboard summarises.
private struct DashboardQuickLinks: View {
    var body: some View {
        HStack(spacing: TessalyticsLayout.gridSpacing) {
            QuickLinkTile("Drives", symbol: "road.lanes", tint: TessalyticsTheme.accent) {
                DriveHistoryView(embedded: true, title: "Drives")
            }
            QuickLinkTile("Charging", symbol: "bolt.car.fill", tint: TessalyticsTheme.positive) {
                ChargeHistoryView(embedded: true, title: "Charging")
            }
            QuickLinkTile("Analysis", symbol: "chart.xyaxis.line", tint: TessalyticsTheme.neutral) {
                AnalyticsDashboardView()
            }
            QuickLinkTile("Battery", symbol: "battery.100percent", tint: TessalyticsTheme.positive) {
                BatteryHealthView()
            }
        }
    }
}

/// Most recent completed drive, with a static route preview, linking to the
/// full drive detail screen.
private struct LatestDriveCard: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    let record: DriveRecord

    @State private var route: [CoordinateDTO] = []

    var body: some View {
        NavigationSectionCard(
            "Latest drive",
            subtitle: ValueFormatting.date(record.startDate),
            symbol: "map.fill",
            tint: TessalyticsTheme.accent
        ) {
            DriveDetailView(driveID: record.driveID)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                RouteSnapshotView(route: route, driveID: record.driveID, height: 168)
                DriveEndpointRow(
                    start: record.startAddress ?? "Start not reported",
                    end: record.endAddress ?? "End not reported"
                )
                HStack(spacing: TessalyticsLayout.gridSpacing) {
                    CompactStat(
                        title: "Distance",
                        value: ValueFormatting.distance(record.distance, units: environment.statusUnits),
                        tint: TessalyticsTheme.accent
                    )
                    CompactStat(
                        title: "Duration",
                        value: ValueFormatting.duration(minutes: record.durationMinutes),
                        tint: TessalyticsTheme.neutral
                    )
                    CompactStat(
                        title: "Efficiency",
                        value: ValueFormatting.efficiency(record.efficiency, units: environment.statusUnits, digits: 0),
                        tint: TessalyticsTheme.positive
                    )
                }
            }
        }
        .task(id: record.driveID) { await loadRoute() }
    }

    private func loadRoute() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        do {
            let detail = try await DriveRepository(context: context).detail(
                client: environment.client(for: profile),
                serverID: profile.id,
                carID: vehicle.id,
                driveID: record.driveID
            )
            route = RouteSimplifier.simplify(detail.driveDetails.map(\.coordinate), tolerance: 0.00025)
        } catch {
            route = []
        }
    }
}

private struct DemoModeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(TessalyticsTheme.accent)
                .accessibilityHidden(true)
            Text("Demo data")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Generated sample")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo data, generated sample")
        .accessibilityIdentifier("demo-mode-banner")
    }
}

private struct RecentDrivePoint: Identifiable {
    let date: Date
    let distance: Double
    var id: Date { date }
}

private struct RecentDrivingChart: View {
    let points: [RecentDrivePoint]
    let units: UnitsDTO?

    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }
    private var total: Double { points.map(\.distance).reduce(0, +) }


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Distance (\(resolvedUnits.lengthSymbol))", point.distance)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [TessalyticsTheme.accentBright, TessalyticsTheme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisTick()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text(distance.formatted(.number.precision(.fractionLength(0))))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .tessalyticsChartAxes(x: "Last 7 days", y: "Distance (\(resolvedUnits.lengthSymbol))")
            .tessalyticsChartStyle()
            .frame(height: 128)
            .accessibilityLabel("Distance driven over the last seven days in \(resolvedUnits.lengthSymbol)")
            .accessibilityValue("Total \(ValueFormatting.distance(total, units: resolvedUnits))")
            .accessibilityIdentifier("home-driving-chart")

            ChartLegend("Distance per day", color: TessalyticsTheme.accent)
        }
    }
}

private struct StatusRefreshCard: View {
    let isRefreshing: Bool
    let message: String?
    let retry: () -> Void

    var body: some View {
        SurfaceCard(tint: TessalyticsTheme.steel) {
            HStack(spacing: 10) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(TessalyticsTheme.steel)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRefreshing ? "Updating status" : "Status not available yet")
                        .font(.subheadline.weight(.semibold))
                    if let message, !isRefreshing {
                        Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if !isRefreshing {
                    Button("Retry", action: retry).buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }
}

/// Where a tap on the hero card leads.
///
/// The card used to answer "battery health" to every tap, including the one on
/// the tyre diagram. Each figure now leads to the screen it is about.
enum VehicleHeroDestination: Hashable, Sendable {
    case batteryHealth
    case drives
    case tyres
    /// The car itself: its name, its specification and what it was rated at new.
    case vehicle
    case map
}

private struct VehicleHeroCard: View {
    @Environment(\.isRenderingSharePoster) private var isRenderingPoster
    /// Tiles for the location map, drawn ahead of a share.
    var posterMap: UIImage?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let vehicle: Vehicle?
    let status: VehicleStatus?
    let units: UnitsDTO?
    let freshnessLabel: String?
    let freshnessColor: Color
    let updatedAt: Date?
    let battery: FleetStatistics.BatteryHealth?
    /// Daily distance for the sparkline, oldest first.
    let activity: [RecentDrivePoint]
    /// Recent average consumption, in the server's per-distance unit.
    let efficiency: Double?
    /// Battery level over the last week, rebuilt from drives and charges.
    let batteryLevels: [BatteryLevelPoint]
    let tyres: TPMSDTO?
    /// The route of the drive in progress, already stabilised so a redraw of this
    /// card does not redraw the line on the map.
    let route: LiveRouteTrail
    /// The whole drive's figures, for the grid under the map.
    let liveTotals: LiveDriveTotals
    let isStreaming: Bool
    /// Whether a drive is in progress, latched so one odd reading cannot rebuild
    /// the card.
    let isDriving: Bool
    /// The last position reported during it. Held by the environment rather than
    /// read off `status`, so a reading without one does not take the map out of
    /// the view tree — see `AppEnvironment.liveCoordinate`.
    let coordinate: CoordinateDTO?
    /// Where the car is, in words. Resolved on the device from the coordinate.
    let placeName: String?
    /// Opens whatever was tapped.
    ///
    /// One closure and a destination rather than a closure per region: the card
    /// grew from "tap it for battery health" to six different answers, and six
    /// stored closures is a parameter list nobody reads.
    let onOpen: (VehicleHeroDestination) -> Void

    private var mapCoordinate: CLLocationCoordinate2D? {
        guard let coordinate, coordinate.isReported else { return nil }
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var summary: VehicleHeroSummary {
        VehicleHeroSummary(status: status, units: units, placeName: placeName)
    }
    private var isLive: Bool { status?.reportsLiveTelemetry ?? false }
    private var modelText: String {
        [TeslaModelNaming.displayName(vehicle?.model), vehicle?.trim?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty ?? "Vehicle details unavailable"
    }
    private var tint: Color {
        switch summary.activity {
        case .charging: TessalyticsTheme.positive
        case .driving: TessalyticsTheme.accentBright
        case .pluggedIn: TessalyticsTheme.warning
        case .parked, .asleep, .offline, .unavailable: TessalyticsTheme.steel
        }
    }

    /// How long the car has been driving or charging is news. How long it has
    /// been asleep is not, so only a notable state contributes its age.
    private var footnote: String {
        let updated = updatedAt.map { "updated at \(Self.readingTime($0))" }
        let age = summary.isNotable ? status?.stateDuration.map { duration in
            "\(summary.stateNoun) for \(duration.elapsedDescription)"
        } : nil
        let parts = [age, updated].compactMap { $0 }
        return parts.isEmpty ? "Waiting for vehicle data" : parts.joined(separator: " · ")
    }

    /// The clock time a reading arrived, to the second.
    static func readingTime(_ date: Date) -> String { ValueFormatting.readingTime(date) }

    private var distanceUnit: String { (units ?? .metricDefaults).lengthSymbol }

    /// The odometer to a tenth.
    ///
    /// A whole number hides the thing this figure is most used for: watching it
    /// move. Rounded to the nearest unit, a short errand changes nothing on
    /// screen, which reads as a stale reading rather than a short drive.
    private var odometerValue: String {
        guard let odometer = status?.odometer else { return "—" }
        return odometer.formatted(.number.precision(.fractionLength(1)))
    }

    private var odometerAccessibilityValue: String {
        guard let odometer = status?.odometer else { return "Unavailable" }
        return "\(odometer.formatted(.number.precision(.fractionLength(0)))) \(distanceUnit)"
    }

    /// The card leads to battery health, and the map on it leads to the map.
    ///
    /// Two buttons around the map rather than one button with the map cut out of
    /// it. A control nested inside another control is unreliable to tap and worse
    /// to hear: SwiftUI collapses the children of a button into a single element,
    /// so a map inside the card's button is not something VoiceOver can reach at
    /// all, whatever gesture is attached to it.
    var body: some View {
        TessalyticsHeroSurface(tint: tint) {
            // One layout, always, with the map inserted into it rather than a
            // separate layout for the days the car is moving. Two branches meant
            // that anything flipping `isDriving` — or one reading arriving
            // without a position — replaced the whole card, `MKMapView` and all,
            // and a map that leaves the view tree comes back as an empty grey
            // rectangle for as long as it takes to redraw. That was the flicker.
            // Nothing here is wrapped in an outer button any more. Each figure
            // leads somewhere of its own, and a control inside another control is
            // both unreliable to tap and invisible to VoiceOver, which collapses
            // a button's children into one element.
            VStack(alignment: .leading, spacing: 12) {
                identity
                if isDriving, let mapCoordinate {
                    mapButton(coordinate: mapCoordinate)
                }
                details
            }
        }
        // A container rather than a plain identifier: an identifier on a view with
        // controls inside it is inherited by every one of them, which renamed the
        // map button after the card and left nothing able to find the map.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vehicle-snapshot-card")
    }

    @ViewBuilder private func mapButton(coordinate: CLLocationCoordinate2D) -> some View {
        if isRenderingPoster {
            RoutePosterMap(
                height: dynamicTypeSize.isAccessibilitySize ? 150 : 128,
                snapshot: posterMap
            )
        } else {
            liveMapButton(coordinate: coordinate)
        }
    }

    private func liveMapButton(coordinate: CLLocationCoordinate2D) -> some View {
        Button { onOpen(.map) } label: {
            LiveLocationMap(
                coordinate: coordinate,
                heading: status?.drivingDetails?.heading,
                route: route,
                height: dynamicTypeSize.isAccessibilitySize ? 150 : 128
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .padding(6)
                    .background(.regularMaterial, in: .circle)
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("The route driven so far")
        .accessibilityHint("Opens the full screen map")
        .accessibilityIdentifier("hero-live-map")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            VehicleHeroHeader(
                name: vehicle?.name?.nilIfEmpty,
                model: modelText,
                freshnessLabel: freshnessLabel,
                freshnessColor: freshnessColor,
                onOpenVehicle: { onOpen(.vehicle) }
            )

            // Only motion and charging get the loud line. The rest of the
            // time the place is the interesting part — but the state is still
            // worth a word, so it rides alongside as a pill.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if summary.isNotable {
                        Label(summary.headline, systemImage: summary.activity.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .tint(tint)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(0.78)
                            .accessibilityIdentifier("vehicle-headline")
                    } else if let place = summary.placeText {
                        Label(place, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("vehicle-place")
                    }
                    Spacer(minLength: 6)
                    // The gear the car is actually in. Reported on every reading
                    // and previously shown nowhere: "Parked" is the app's word
                    // for it, and P is the car's.
                    if let gear = summary.shiftState {
                        ShiftStateBadge(gear: gear)
                    }
                    if isDriving {
                        LiveIndicator(isStreaming: isStreaming)
                    } else {
                        StatusBadge(text: summary.stateNoun, color: tint)
                            .accessibilityIdentifier("vehicle-state-pill")
                    }
                }

                // "Driving" on its own says nothing a glance at the road does
                // not. Where the car is, and whether it is steering itself, are
                // the two things the screen knows that the driver does not — and
                // at a red light, with the speed at zero, they are the only two
                // things on the line worth reading.
                if summary.isNotable {
                    liveDetailLine
                }
            }
        }
    }

    @ViewBuilder private var liveDetailLine: some View {
        let place = summary.placeText
        if place != nil || summary.selfDriving != nil {
            HStack(spacing: 8) {
                if let place {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Location")
                        .accessibilityValue(place)
                        .accessibilityIdentifier("vehicle-place")
                }
                Spacer(minLength: 4)
                if let mode = summary.selfDriving {
                    SelfDrivingBadge(mode: mode)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
                // Each figure is a control that leads where the figure is about.
                // The whole card used to open battery health, so tapping the
                // tyres to see the tyres took you to the battery.
                HStack(alignment: .center, spacing: 14) {
                    Button { onOpen(.batteryHealth) } label: {
                        BatteryRingGauge(
                            level: summary.batteryFraction,
                            limit: summary.chargeLimitFraction,
                            isCharging: summary.activity == .charging,
                            diameter: dynamicTypeSize.isAccessibilitySize ? 92 : 76
                        )
                        .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens battery health")
                    .accessibilityIdentifier("vehicle-snapshot-battery")

                    VStack(alignment: .leading, spacing: 8) {
                        Button { onOpen(.batteryHealth) } label: {
                            HeroFigure(
                                value: summary.rangeValue,
                                label: summary.rangeLabel,
                                symbol: "gauge.open.with.lines.needle.33percent",
                                tint: TessalyticsTheme.accent
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Estimated range")
                        .accessibilityValue(summary.rangeAccessibilityValue)
                        .accessibilityHint("Opens battery health")
                        .accessibilityIdentifier("vehicle-snapshot-range")

                        // The odometer is a driving figure, so it leads to the
                        // drives that produced it.
                        Button { onOpen(.drives) } label: {
                            HeroFigure(
                                value: odometerValue,
                                label: "\(distanceUnit) on the odometer",
                                symbol: "road.lanes",
                                tint: TessalyticsTheme.steel
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Odometer")
                        .accessibilityValue(odometerAccessibilityValue)
                        .accessibilityHint("Opens the drive history")
                        .accessibilityIdentifier("vehicle-snapshot-odometer")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Placed where the wheels are: four numbers in a row cannot
                    // say which corner each belongs to.
                    if !dynamicTypeSize.isAccessibilitySize, tyres?.hasAnyReading == true {
                        Button { onOpen(.tyres) } label: {
                            TirePressureDiagram(pressures: tyres, units: units, height: 84)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens tyre pressures")
                        .accessibilityIdentifier("vehicle-snapshot-tyres")
                    }
                }

                if let charging = summary.charging {
                    ChargingSnapshotRow(charging: charging, tint: tint)
                }

                if isDriving {
                    Divider()
                    LiveMetricGrid(
                        metrics: LiveMetrics.hero(status: status, totals: liveTotals, units: units)
                    )
                    .accessibilityIdentifier("hero-live-metrics")
                } else if !batteryLevels.isEmpty {
                    Divider()
                    Button { onOpen(.batteryHealth) } label: {
                        HeroBatteryLevelChart(points: batteryLevels).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens battery health")
                }

                Divider()

                // The two questions a glance at the car is usually asking: how
                // much has it been driven lately, and how efficiently.
                if !activity.isEmpty {
                    HeroActivityStrip(
                        points: activity,
                        efficiency: efficiency,
                        units: units,
                        health: battery?.healthPercent,
                        onOpen: onOpen
                    )
                }

                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
        }
    }
}

private struct VehicleHeroHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let name: String?
    let model: String
    let freshnessLabel: String?
    let freshnessColor: Color
    let onOpenVehicle: () -> Void

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                identity
                if let freshnessLabel {
                    StatusBadge(text: freshnessLabel, color: freshnessColor)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                identity
                Spacer(minLength: 8)
                if let freshnessLabel {
                    StatusBadge(text: freshnessLabel, color: freshnessColor)
                }
            }
        }
    }

    /// The vehicle name lives here as well as in the navigation title: on iPad
    /// the tab bar occupies the navigation bar and the title is not displayed at
    /// all, so the card has to say which car it is describing.
    private var identity: some View {
        Button(action: onOpenVehicle) {
            VStack(alignment: .leading, spacing: 2) {
                if let name {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(model.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this vehicle's settings")
        .accessibilityIdentifier("vehicle-snapshot-identity")
    }
}

struct DashboardHistorySummary: Equatable {
    var lastDriveDistance: Double?
    var lastDriveDate: Date?
    var lastDriveDurationMinutes: Int?
    var weeklyDistance: Double = 0
    var weeklyDrives: Int = 0
    var lastChargeEnergy: Double?
    var lastChargeDate: Date?

    func lastDriveText(units: UnitsDTO?) -> String {
        guard let distance = lastDriveDistance else { return "No drives synced" }
        return "Last \(ValueFormatting.distance(distance, units: units, digits: 1))"
    }

    func weeklyText(units: UnitsDTO?) -> String {
        guard weeklyDrives > 0 else { return "No drives in 7 days" }
        return "\(ValueFormatting.distance(weeklyDistance, units: units, digits: 0)) / 7 days"
    }

    func lastChargeText() -> String {
        guard let energy = lastChargeEnergy else { return "No charges synced" }
        return "Charged \(ValueFormatting.number(energy, unit: "kWh"))"
    }
}

private struct SnapshotFact: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let text: String
    let symbol: String
    let tint: Color
    var accessibilityID: String?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
            .tint(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.09), in: .rect(cornerRadius: 9))
            .accessibilityIdentifier(accessibilityID ?? "")
    }
}

private struct ChargingSnapshotRow: View {
    let charging: VehicleHeroSummary.Charging
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(charging.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(charging.limitText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: charging.progress)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Charging progress")
    }
}

struct VehicleHeroSummary: Equatable {
    enum Activity: Equatable {
        case driving, charging, pluggedIn, parked, asleep, offline, unavailable

        var symbol: String {
            switch self {
            case .driving: "location.north.line.fill"
            case .charging: "bolt.fill"
            case .pluggedIn: "powerplug.fill"
            case .parked: "parkingsign.circle.fill"
            case .asleep: "moon.zzz.fill"
            case .offline: "wifi.slash"
            case .unavailable: "exclamationmark.circle"
            }
        }
    }

    struct Security: Equatable {
        let text: String
        let symbol: String
        let needsAttention: Bool
    }

    struct Charging: Equatable {
        let progress: Double
        let detail: String
        let limitText: String
    }

    let activity: Activity
    let headline: String
    let stateNoun: String
    /// Whether the state is worth announcing at all.
    ///
    /// A car is parked, asleep or offline for the overwhelming majority of its
    /// life, so leading with "Offline at ..." spends the most prominent line in
    /// the app on the least surprising fact. Only motion and charging earn it.
    let isNotable: Bool
    /// Where the car is, without a state word in front of it.
    let placeText: String?
    let batteryText: String
    let batteryAccessibilityValue: String
    let rangeValue: String
    let rangeLabel: String
    let rangeAccessibilityValue: String
    let security: Security
    let climateText: String
    let charging: Charging?
    /// 0...1 for the ring gauge, nil when the level is unknown.
    let batteryFraction: Double?
    /// The configured charge limit as a fraction, for the ring's tick.
    let chargeLimitFraction: Double?
    /// What is steering, when the server says. Nil is "the server does not
    /// report it", and draws nothing at all.
    let selfDriving: SelfDrivingMode?
    /// Whether the car is in a drive and standing still.
    let isStoppedInDrive: Bool
    /// The gear the car reports, uppercased — P, R, N or D — or nil when the
    /// server says nothing.
    let shiftState: String?

    /// - Parameter placeName: where the car is, resolved on the device from its
    ///   coordinate. A geofence still wins when there is one: "Home" is what the
    ///   owner called the place, and no geocoder will improve on that.
    init(status: VehicleStatus?, units: UnitsDTO?, placeName: String? = nil) {
        let resolvedUnits = units ?? .metricDefaults
        // Resolved on this device from the coordinate, and from nothing else.
        //
        // The server's geofence was the first choice here and it was wrong more
        // often than it was right: TeslaMate names a place only when a *drive*
        // ended inside one an owner had drawn, so a car parked anywhere else kept
        // reporting the last named place it had visited — a home address, shown
        // for days, for a car that was nowhere near it. A geocoded coordinate is
        // about where the car is now, which is the only thing this line claims.
        let location = placeName?.nilIfEmpty
        let state = status?.state?.lowercased()
        let shift = status?.drivingDetails?.shiftState?.uppercased()
        let chargingState = status?.chargingDetails?.chargingState?.lowercased()
        let isDriving = state == "driving" || (shift.map { ["D", "R", "N"].contains($0) } ?? false)
        let isCharging = chargingState == "charging" || (status?.chargingDetails?.reportedPower ?? 0) > 0
        let isPluggedIn = status?.chargingDetails?.pluggedIn == true

        placeText = location
        shiftState = shift?.nilIfEmpty
        selfDriving = status?.selfDrivingMode
        isStoppedInDrive = status?.isStoppedInDrive ?? false
        if isDriving {
            activity = .driving
            let speed = Self.value(status?.drivingDetails?.speed, unit: resolvedUnits.speedSymbol)
            // A car at a red light is not "Driving · 0 mph". Standing still in
            // the middle of a journey is its own thing, and saying so is the
            // difference between a screen that looks stuck and one that is
            // telling you what the car is doing.
            let gear = status?.drivingDetails?.notableGear
            if let gear {
                // Reverse and neutral outrank the speed: they are the surprising
                // thing about the reading, and the speed is on the grid below.
                headline = gear
                stateNoun = gear
            } else if status?.isStoppedInDrive == true {
                headline = "Stopped"
                stateNoun = "Stopped"
            } else {
                headline = speed.map { "Driving · \($0)" } ?? "Driving"
                stateNoun = "Driving"
            }
            isNotable = true
        } else if isCharging {
            activity = .charging
            let power = Self.value(status?.chargingDetails?.reportedPower, unit: "kW", maximumFractionDigits: 0)
            headline = power.map { "Charging · \($0)" } ?? "Charging"
            stateNoun = "Charging"
            isNotable = true
        } else if isPluggedIn {
            activity = .pluggedIn
            headline = chargingState == "complete" ? "Charge complete" : "Plugged in"
            stateNoun = "Plugged in"
            isNotable = true
        } else if state == "asleep" || state == "suspended" {
            activity = .asleep
            headline = location ?? "Asleep"
            stateNoun = "Asleep"
            isNotable = false
        } else if state == "offline" {
            activity = .offline
            headline = location ?? "Last seen"
            stateNoun = "Offline"
            isNotable = false
        } else if status != nil {
            activity = .parked
            headline = location ?? "Parked"
            stateNoun = "Parked"
            isNotable = false
        } else {
            activity = .unavailable
            headline = "Waiting for vehicle"
            stateNoun = "Waiting"
            isNotable = false
        }

        if let level = status?.batteryDetails?.batteryLevel {
            batteryText = level.formatted()
            batteryAccessibilityValue = "\(level) percent"
            batteryFraction = Double(level) / 100
        } else {
            batteryText = "—"
            batteryAccessibilityValue = "Unavailable"
            batteryFraction = nil
        }
        chargeLimitFraction = status?.chargingDetails?.reportedChargeLimit.map { Double($0) / 100 }

        // `est_battery_range` is reported as 0 while the car sleeps, which showed
        // "0 mi estimated range" next to a battery at 80%.
        if let range = status?.batteryDetails?.displayRange {
            // Two decimals, because the server reports them and rounding them off
            // made a range that was visibly falling look like one that was stuck.
            rangeValue = range.value.formatted(.number.precision(.fractionLength(2)))
            rangeLabel = "\(resolvedUnits.lengthSymbol) \(range.label)"
            rangeAccessibilityValue = "\(rangeValue) \(resolvedUnits.lengthSymbol), \(range.label)"
        } else {
            rangeValue = "—"
            rangeLabel = "range unavailable"
            rangeAccessibilityValue = "Unavailable"
        }

        security = Self.security(status?.carStatus, isLive: status?.reportsLiveTelemetry ?? false)
        climateText = Self.climate(status?.climateDetails, temperatureUnit: resolvedUnits.temperatureSymbol)
        charging = Self.charging(status: status, isPluggedIn: isPluggedIn)
    }

    /// While the car is asleep or offline TeslaMateApi returns `locked: false`
    /// because it has no reading, not because the car is unlocked. Claiming
    /// "Unlocked" there is the single most alarming thing this app could get
    /// wrong, so an unknown state is reported as unknown.
    private static func security(_ status: CarStatusDTO?, isLive: Bool) -> Security {
        guard let status else { return Security(text: "Security unavailable", symbol: "lock.slash", needsAttention: false) }
        guard isLive else {
            return Security(text: "Lock state unknown", symbol: "lock.trianglebadge.exclamationmark", needsAttention: false)
        }
        if status.doorsOpen == true || status.windowsOpen == true || status.trunkOpen == true || status.frunkOpen == true {
            return Security(text: "Open access", symbol: "exclamationmark.triangle.fill", needsAttention: true)
        }
        if status.locked == false {
            return Security(text: "Unlocked", symbol: "lock.open.fill", needsAttention: true)
        }
        if status.locked == true, status.sentryMode == true {
            return Security(text: "Locked · Sentry", symbol: "lock.shield.fill", needsAttention: false)
        }
        if status.locked == true {
            return Security(text: "Locked", symbol: "lock.fill", needsAttention: false)
        }
        return Security(text: "Lock unavailable", symbol: "lock.slash", needsAttention: false)
    }

    private static func climate(_ climate: ClimateDetailsDTO?, temperatureUnit: String) -> String {
        guard let temperature = climate?.insideTemp else { return climate?.isClimateOn == true ? "Climate on" : "Cabin unavailable" }
        let value = temperature.formatted(.number.precision(.fractionLength(0...1)))
        return climate?.isClimateOn == true ? "Climate on · \(value)\(temperatureUnit)" : "Cabin \(value)\(temperatureUnit)"
    }

    private static func charging(status: VehicleStatus?, isPluggedIn: Bool) -> Charging? {
        guard isPluggedIn, let level = status?.batteryDetails?.batteryLevel else { return nil }
        let limit = status?.chargingDetails?.reportedChargeLimit ?? 100
        let progress = min(Double(level) / Double(max(limit, 1)), 1)
        let detail: String
        if let hours = status?.chargingDetails?.reportedTimeToFull {
            let minutes = Int((hours * 60).rounded())
            detail = "\(ValueFormatting.duration(minutes: minutes)) remaining"
        } else {
            detail = status?.chargingDetails?.reportedState ?? "Connected"
        }
        return Charging(progress: progress, detail: detail, limitText: "\(level)% → \(limit)%")
    }

    private static func value(_ value: Double?, unit: String?, maximumFractionDigits: Int = 0) -> String? {
        guard let value else { return nil }
        let number = value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
        return [number, unit].compactMap { $0 }.joined(separator: " ")
    }
}

private struct ChargingStatusCard: View {
    let status: VehicleStatus

    private var level: Int? { status.batteryDetails?.batteryLevel }
    private var limit: Int? { status.chargingDetails?.reportedChargeLimit }

    var body: some View {
        NavigationSectionCard(
            "Charging",
            subtitle: status.chargingDetails?.pluggedIn == true ? "Connected" : "Not connected",
            symbol: "bolt.car.fill",
            tint: TessalyticsTheme.positive
        ) {
            ChargeHistoryView(embedded: true, title: "Charging")
        } content: {
            VStack(spacing: 8) {
                if let level, let limit {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Battery to charge limit")
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 12)
                            Text("\(level)% / \(limit)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(min(level, limit)), total: Double(max(limit, 1)))
                            .tint(TessalyticsTheme.positive)
                    }
                }
                DetailRow(title: "State", value: status.chargingDetails?.reportedState ?? "Not reported")
                DetailRow(title: "Power", value: value(status.chargingDetails?.reportedPower, unit: "kW"))
                DetailRow(title: "Energy added", value: value(status.chargingDetails?.reportedEnergyAdded, unit: "kWh"))
                DetailRow(
                    title: "Time remaining",
                    value: status.chargingDetails?.reportedTimeToFull.map {
                        ValueFormatting.duration(minutes: Int(($0 * 60).rounded()))
                    } ?? "Not reported"
                )
            }
        }
    }

    /// Zero-valued charging telemetry means "not reported", not "zero kilowatts".
    private func value(_ value: Double?, unit: String) -> String {
        guard let value else { return "Not reported" }
        return ValueFormatting.number(value, unit: unit)
    }
}

private struct VehicleActivityCard: View {
    let vehicle: Vehicle?
    let weeklyDrives: Int

    var body: some View {
        NavigationSectionCard(
            "Synchronized history",
            subtitle: "Reported by TeslaMate",
            symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            tint: TessalyticsTheme.neutral
        ) {
            DriveHistoryView(embedded: true, title: "Drives")
        } content: {
            LazyVGrid(
                columns: TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.statMinWidth),
                spacing: TessalyticsLayout.gridSpacing
            ) {
                CompactStat(
                    title: "Drives",
                    value: vehicle?.totalDrives?.formatted() ?? "—",
                    detail: weeklyDrives > 0 ? "\(weeklyDrives) this week" : nil,
                    tint: TessalyticsTheme.accent
                )
                CompactStat(
                    title: "Charges",
                    value: vehicle?.totalCharges?.formatted() ?? "—",
                    tint: TessalyticsTheme.positive
                )
                CompactStat(
                    title: "Updates",
                    value: vehicle?.totalUpdates?.formatted() ?? "—",
                    tint: TessalyticsTheme.steel
                )
            }
        }
    }
}

private struct VehicleSecurityCard: View {
    let status: VehicleStatus
    /// The last status seen while the car was awake, used when the live one has
    /// nothing to report.
    let lastLive: VehicleStatus?
    let lastLiveAt: Date?
    private let columns = TessalyticsLayout.metricColumns(minimum: TessalyticsLayout.stateMinWidth)

    private var isLive: Bool { status.reportsLiveTelemetry }

    /// Live when the car is awake, otherwise the last waking reading.
    ///
    /// Showing six tiles of "Unknown" was honest and useless. What an owner wants
    /// when the car is asleep is what it was doing when it last spoke, said
    /// plainly as of that moment.
    private var readings: CarStatusDTO? {
        isLive ? status.carStatus : lastLive?.carStatus
    }

    private var hasHistory: Bool { !isLive && readings != nil }

    private var subtitle: String? {
        if isLive { return nil }
        guard hasHistory else { return "Never seen awake — no readings yet" }
        guard let lastLiveAt else { return "Last known state" }
        return "As of \(lastLiveAt.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        SectionCard(
            "Vehicle state",
            subtitle: subtitle,
            symbol: "lock.shield.fill",
            tint: isLive ? TessalyticsTheme.neutral : TessalyticsTheme.steel
        ) {
            LazyVGrid(columns: columns, spacing: TessalyticsLayout.gridSpacing) {
                VehicleStateItem(title: "Locked", value: readings?.locked, symbol: "lock.fill", isLive: isLive, isHistoric: hasHistory)
                VehicleStateItem(title: "Sentry", value: readings?.sentryMode, symbol: "shield.fill", isLive: isLive, isHistoric: hasHistory)
                VehicleStateItem(title: "Doors", value: readings?.doorsOpen, symbol: "door.left.hand.open", healthyWhenFalse: true, isLive: isLive, isHistoric: hasHistory)
                VehicleStateItem(title: "Windows", value: readings?.windowsOpen, symbol: "rectangle.split.3x1", healthyWhenFalse: true, isLive: isLive, isHistoric: hasHistory)
                VehicleStateItem(title: "Trunk", value: readings?.trunkOpen, symbol: "car.rear", healthyWhenFalse: true, isLive: isLive, isHistoric: hasHistory)
                VehicleStateItem(title: "Frunk", value: readings?.frunkOpen, symbol: "car.front.waves.up", healthyWhenFalse: true, isLive: isLive, isHistoric: hasHistory)
            }
        }
    }
}

private struct VehicleStateItem: View {
    let title: String
    let value: Bool?
    let symbol: String
    var healthyWhenFalse = false
    var isLive = true
    /// The value came from the last waking reading, not from now.
    var isHistoric = false

    private var isHealthy: Bool? {
        guard isLive || isHistoric else { return nil }
        return value.map { healthyWhenFalse ? !$0 : $0 }
    }
    private var stateText: String {
        guard isLive || isHistoric else { return "Unknown" }
        guard let value else { return "Unavailable" }
        if healthyWhenFalse { return value ? "Open" : "Closed" }
        return value ? "On" : "Off"
    }
    /// A remembered reading is drawn muted: it is a fact about the past, and the
    /// green of a live "Locked" would claim more than the app knows.
    private var tint: Color {
        guard let isHealthy else { return TessalyticsTheme.steel }
        if isHistoric { return TessalyticsTheme.steel }
        return isHealthy ? TessalyticsTheme.positive : TessalyticsTheme.warning
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(stateText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(stateText)
    }
}

private struct TirePressureCard: View {
    let status: VehicleStatus
    let units: UnitsDTO?

    var body: some View {
        SectionCard(
            "Tire pressures",
            // TeslaMate returns 0 psi for tyres it has no reading for, which used
            // to render as a set of four "0.0 psi" values.
            subtitle: status.tpmsDetails?.hasAnyReading == true ? nil : "No sensor readings in the last poll",
            symbol: "gauge.with.dots.needle.50percent",
            tint: TessalyticsTheme.neutral
        ) {
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    TireValue(title: "Front left", value: TPMSDTO.reported(status.tpmsDetails?.tpmsPressureFl), units: units)
                    TireValue(title: "Front right", value: TPMSDTO.reported(status.tpmsDetails?.tpmsPressureFr), units: units)
                }
                Divider().gridCellColumns(2)
                GridRow {
                    TireValue(title: "Rear left", value: TPMSDTO.reported(status.tpmsDetails?.tpmsPressureRl), units: units)
                    TireValue(title: "Rear right", value: TPMSDTO.reported(status.tpmsDetails?.tpmsPressureRr), units: units)
                }
            }
        }
    }
}

private struct TireValue: View {
    let title: String
    let value: Double?
    let units: UnitsDTO?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value == nil ? "Not reported" : ValueFormatting.pressure(value, units: units))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct VehicleDetailsCard: View {
    let status: VehicleStatus
    /// Where the car is, resolved on this device. The server's geofence used to
    /// fill this row and named the last place a drive happened to end inside one.
    let placeName: String?

    var body: some View {
        NavigationSectionCard(
            "Software & details",
            subtitle: status.carVersions?.reportedUpdateVersion.map { "Update \($0) available" }
                ?? "Installed firmware and logger health",
            symbol: "info.circle.fill",
            tint: TessalyticsTheme.neutral
        ) {
            SoftwareUpdatesView()
        } content: {
            VStack(spacing: 12) {
                DetailRow(
                    title: "Location",
                    value: placeName ?? "Not reported",
                    symbol: "mappin.and.ellipse"
                )
                DetailRow(
                    title: "Software",
                    value: status.carVersions?.reportedVersion ?? "Not reported",
                    symbol: "shippingbox.fill"
                )
                DetailRow(
                    title: "Logger",
                    value: status.carStatus?.healthy == true ? "Healthy" : "Unavailable",
                    symbol: "waveform.path.ecg"
                )
            }
        }
    }
}

/// One headline figure beside the battery ring: a value, its unit, and an icon.
private struct HeroFigure: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// The bottom band of the hero: recent activity as a sparkline, beside the two
/// figures that say whether the car is being used well.
private struct HeroActivityStrip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let points: [RecentDrivePoint]
    let efficiency: Double?
    let units: UnitsDTO?
    let health: Double?
    let onOpen: (VehicleHeroDestination) -> Void

    private var resolvedUnits: UnitsDTO { units ?? .metricDefaults }
    private var total: Double { points.map(\.distance).reduce(0, +) }
    private var sparklinePoints: [ExplorableChartPoint] {
        points.enumerated().map { index, point in
            ExplorableChartPoint(id: index, label: "\(index)", value: point.distance)
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                sparkline
                figures
            }
        } else {
            HStack(alignment: .bottom, spacing: 14) {
                sparkline
                figures
            }
        }
    }

    /// No axes and no legend: at this size the shape is the information, and the
    /// total beside it supplies the scale.
    private var sparkline: some View {
        Button { onOpen(.drives) } label: { sparklineContent.contentShape(.rect) }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the drive history")
            .accessibilityIdentifier("hero-recent-driving")
    }

    private var sparklineContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Chart(sparklinePoints) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Distance", point.value)
                )
                .foregroundStyle(TessalyticsTheme.accent.opacity(0.85))
                .clipShape(.rect(cornerRadius: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Distance driven each day over the last \(points.count) days")
            .accessibilityValue(ValueFormatting.distance(total, units: resolvedUnits, digits: 0))

            Text("\(ValueFormatting.distance(total, units: resolvedUnits, digits: 0)) · \(points.count) days")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var figures: some View {
        HStack(spacing: 12) {
            if let efficiency {
                // Consumption is a fact about the driving, so it leads there.
                Button { onOpen(.drives) } label: {
                    HeroFigure(
                        value: efficiency.formatted(.number.precision(.fractionLength(0))),
                        label: "Wh/\(resolvedUnits.lengthSymbol)",
                        symbol: "leaf.fill",
                        tint: TessalyticsTheme.positive
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the drive history")
            }
            if let health {
                Button { onOpen(.batteryHealth) } label: {
                    healthFigure(health).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens battery health")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func healthFigure(_ health: Double) -> some View {
        HeroFigure(
            value: ValueFormatting.percentage(health / 100, digits: 1),
            label: "health",
            symbol: "heart.text.square.fill",
            tint: health >= 90 ? TessalyticsTheme.positive : TessalyticsTheme.warning
        )
    }
}

/// Battery level across the last week, in place of the three summary chips.
///
/// The chips restated numbers already on the card — the last drive, the week's
/// distance, the last charge — where the shape of the week says more: how deep
/// the car is run down, how often it is plugged in, and whether it is being
/// charged to the same level each time.
private struct HeroBatteryLevelChart: View {
    let points: [BatteryLevelPoint]

    private var domain: ClosedRange<Double> {
        let levels = points.map(\.level)
        guard let low = levels.min(), let high = levels.max() else { return 0...100 }
        // Padded, but never beyond the bounds a percentage actually has.
        return max(low - 8, 0)...min(high + 8, 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Chart(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Battery", point.level),
                    stacking: .unstacked
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(
                        colors: [TessalyticsTheme.positive.opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Battery", point.level)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(TessalyticsTheme.positive)
            }
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                    AxisValueLabel {
                        if let level = value.as(Double.self) {
                            Text("\(level.formatted(.number.precision(.fractionLength(0))))%")
                                .font(.system(size: 9).monospacedDigit())
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.1))
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9))
                }
            }
            .frame(height: 62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery level over the last seven days")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("hero-battery-level-chart")

            Text("Battery level · 7 days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: String {
        let levels = points.map(\.level)
        guard let low = levels.min(), let high = levels.max(), let latest = points.last?.level else {
            return "No readings"
        }
        return "now \(Int(latest)) percent, between \(Int(low)) and \(Int(high)) percent"
    }
}

/// The figures that matter while the car is moving.
///
/// Replaces the week-long battery chart for the duration of a drive: the shape of
/// the last seven days is not what someone glancing at a mounted phone needs.
/// The figures themselves are assembled by `LiveMetrics`, so the card and the
/// full-screen map cannot disagree about them.
