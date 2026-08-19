import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    private let metricColumns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        NavigationStack {
            TessalyticsScreen {
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
            .navigationTitle(environment.selectedVehicle?.name ?? "Status")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { vehicleMenu }
            }
            .safeAreaInset(edge: .top) {
                if environment.isOffline { OfflineBanner() }
            }
            .task {
                if scenePhase == .active { environment.startStatusPolling() }
            }
            .onDisappear { environment.stopStatusPolling() }
            .onChange(of: scenePhase) { _, phase in
                phase == .active ? environment.startStatusPolling() : environment.stopStatusPolling()
            }
            .refreshable { await environment.refreshStatus() }
        }
        .accessibilityIdentifier("dashboard-screen")
    }

    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                VehicleHeroCard(
                    vehicle: environment.selectedVehicle,
                    status: environment.status,
                    units: environment.statusUnits,
                    freshnessLabel: freshnessLabel,
                    freshnessColor: freshnessColor,
                    updatedAt: environment.statusFetchedAt
                )

                if environment.isOwnerConnected {
                    DirectTeslaControlsCard()
                }

                if let status = environment.status {
                    LazyVGrid(columns: metricColumns, spacing: 8) {
                        MetricCard(
                            title: "Odometer",
                            value: ValueFormatting.number(status.odometer, unit: ""),
                            symbol: "gauge.open.with.lines.needle.33percent",
                            tint: TessalyticsTheme.neutral
                        )
                        MetricCard(
                            title: "Inside temperature",
                            value: ValueFormatting.number(status.climateDetails?.insideTemp, unit: "°"),
                            symbol: "thermometer.medium",
                            tint: TessalyticsTheme.warning
                        )
                        MetricCard(
                            title: "Outside temperature",
                            value: ValueFormatting.number(status.climateDetails?.outsideTemp, unit: "°"),
                            symbol: "thermometer.sun",
                            tint: TessalyticsTheme.warning
                        )
                    }

                    VehicleActivityCard(vehicle: environment.selectedVehicle)
                    ChargingStatusCard(status: status)
                    VehicleSecurityCard(status: status)
                    TirePressureCard(status: status)
                    VehicleDetailsCard(status: status)
                } else {
                    LoadingPanel(title: "Loading last reported status", symbol: "car.side")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var freshnessLabel: String {
        if environment.isOffline { return "Stale" }
        if environment.statusUsesOwnerAPI { return "Direct live" }
        guard let fetched = environment.statusFetchedAt else { return "Connecting" }
        if Date().timeIntervalSince(fetched) > 120 { return "Stale" }
        return environment.status?.state == "online"
            ? "Live"
            : (environment.status?.state?.capitalized ?? "Live")
    }

    private var freshnessColor: Color {
        environment.isOffline ? TessalyticsTheme.warning : environment.status?.state == "online" ? TessalyticsTheme.positive : TessalyticsTheme.steel
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

private struct VehicleHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let vehicle: Vehicle?
    let status: VehicleStatus?
    let units: UnitsDTO?
    let freshnessLabel: String
    let freshnessColor: Color
    let updatedAt: Date?

    private var summary: VehicleHeroSummary { VehicleHeroSummary(status: status, units: units) }
    private var modelText: String {
        [vehicle?.model, vehicle?.trim]
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

    var body: some View {
        TessalyticsHeroSurface(tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                VehicleHeroHeader(model: modelText, freshnessLabel: freshnessLabel, freshnessColor: freshnessColor)

                Label(summary.headline, systemImage: summary.activity.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .tint(tint)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.78)

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(summary.batteryText)
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                        Text("%")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Battery level")
                    .accessibilityValue(summary.batteryAccessibilityValue)
                    .accessibilityIdentifier("vehicle-snapshot-battery")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.rangeValue)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(summary.rangeLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Estimated range")
                    .accessibilityValue(summary.rangeAccessibilityValue)
                    .accessibilityIdentifier("vehicle-snapshot-range")
                }
                .foregroundStyle(.white)

                if let charging = summary.charging {
                    ChargingSnapshotRow(charging: charging, tint: tint)
                }

                Divider().overlay(.white.opacity(0.14))

                SnapshotFactsRow(summary: summary)

                Text(updatedAt.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Waiting for vehicle data")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityIdentifier("vehicle-snapshot-card")
    }
}

private struct VehicleHeroHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: String
    let freshnessLabel: String
    let freshnessColor: Color

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                modelLabel
                StatusBadge(text: freshnessLabel, color: freshnessColor)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                modelLabel
                Spacer(minLength: 8)
                StatusBadge(text: freshnessLabel, color: freshnessColor)
            }
        }
    }

    private var modelLabel: some View {
        Text(model.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }
}

private struct SnapshotFactsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: VehicleHeroSummary

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) { facts }
        } else {
            HStack(spacing: 6) { facts }
        }
    }

    @ViewBuilder private var facts: some View {
        SnapshotFact(
            text: summary.security.text,
            symbol: summary.security.symbol,
            tint: summary.security.needsAttention ? TessalyticsTheme.warning : .white,
            accessibilityID: "vehicle-snapshot-security"
        )
        SnapshotFact(text: summary.climateText, symbol: "thermometer.medium", tint: .white)
        SnapshotFact(text: summary.locationText, symbol: "location.fill", tint: .white)
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
            .foregroundStyle(.white.opacity(0.76))
            .symbolRenderingMode(.hierarchical)
            .tint(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 9))
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
                    .foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 8)
                Text(charging.limitText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
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
    let batteryText: String
    let batteryAccessibilityValue: String
    let rangeValue: String
    let rangeLabel: String
    let rangeAccessibilityValue: String
    let security: Security
    let climateText: String
    let locationText: String
    let charging: Charging?

    init(status: VehicleStatus?, units: UnitsDTO?) {
        let location = status?.carGeodata?.geofence?.nilIfEmpty
        let locationSuffix = location.map { " at \($0)" } ?? ""
        let state = status?.state?.lowercased()
        let shift = status?.drivingDetails?.shiftState?.uppercased()
        let chargingState = status?.chargingDetails?.chargingState?.lowercased()
        let isDriving = state == "driving" || (shift.map { ["D", "R", "N"].contains($0) } ?? false)
        let isCharging = chargingState == "charging" || (status?.chargingDetails?.chargerPower ?? 0) > 0
        let isPluggedIn = status?.chargingDetails?.pluggedIn == true

        if isDriving {
            activity = .driving
            let speedUnit = units?.unitOfLength?.lowercased() == "mi" ? "mph" : units?.unitOfLength.map { "\($0)/h" }
            let speed = Self.value(status?.drivingDetails?.speed, unit: speedUnit)
            headline = speed.map { "Driving · \($0)" } ?? "Driving"
        } else if isCharging {
            activity = .charging
            let power = Self.value(status?.chargingDetails?.chargerPower, unit: "kW", maximumFractionDigits: 0)
            headline = power.map { "Charging · \($0)" } ?? "Charging"
        } else if isPluggedIn {
            activity = .pluggedIn
            headline = chargingState == "complete" ? "Charge complete" : "Plugged in"
        } else if state == "asleep" {
            activity = .asleep
            headline = "Asleep\(locationSuffix)"
        } else if state == "offline" {
            activity = .offline
            headline = "Offline\(locationSuffix)"
        } else if status != nil {
            activity = .parked
            headline = "Parked\(locationSuffix)"
        } else {
            activity = .unavailable
            headline = "Waiting for vehicle"
        }

        if let level = status?.batteryDetails?.batteryLevel {
            batteryText = level.formatted()
            batteryAccessibilityValue = "\(level) percent"
        } else {
            batteryText = "—"
            batteryAccessibilityValue = "Unavailable"
        }

        if let range = status?.batteryDetails?.estBatteryRange {
            rangeValue = range.formatted(.number.precision(.fractionLength(0)))
            rangeLabel = [units?.unitOfLength, "estimated range"].compactMap { $0 }.joined(separator: " ")
            rangeAccessibilityValue = [rangeValue, units?.unitOfLength].compactMap { $0 }.joined(separator: " ")
        } else {
            rangeValue = "—"
            rangeLabel = "estimated range"
            rangeAccessibilityValue = "Unavailable"
        }

        security = Self.security(status?.carStatus)
        climateText = Self.climate(status?.climateDetails, temperatureUnit: units?.unitOfTemperature)
        locationText = location ?? "Location unavailable"
        charging = Self.charging(status: status, isPluggedIn: isPluggedIn)
    }

    private static func security(_ status: CarStatusDTO?) -> Security {
        guard let status else { return Security(text: "Security unavailable", symbol: "lock.slash", needsAttention: false) }
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

    private static func climate(_ climate: ClimateDetailsDTO?, temperatureUnit: String?) -> String {
        guard let temperature = climate?.insideTemp else { return climate?.isClimateOn == true ? "Climate on" : "Cabin unavailable" }
        let value = temperature.formatted(.number.precision(.fractionLength(0...1)))
        let suffix = temperatureUnit.map { "°\($0.uppercased())" } ?? "°"
        return climate?.isClimateOn == true ? "Climate on · \(value)\(suffix)" : "Cabin \(value)\(suffix)"
    }

    private static func charging(status: VehicleStatus?, isPluggedIn: Bool) -> Charging? {
        guard isPluggedIn, let level = status?.batteryDetails?.batteryLevel else { return nil }
        let limit = max(status?.chargingDetails?.chargeLimitSoc ?? 100, 1)
        let progress = min(Double(level) / Double(limit), 1)
        let detail: String
        if let hours = status?.chargingDetails?.timeToFullCharge, hours > 0 {
            let minutes = Int((hours * 60).rounded())
            detail = "\(ValueFormatting.duration(minutes: minutes)) remaining"
        } else {
            detail = status?.chargingDetails?.chargingState ?? "Connected"
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

    private var batteryLevel: Double { Double(status.batteryDetails?.batteryLevel ?? 0) }
    private var chargeLimit: Double { Double(status.chargingDetails?.chargeLimitSoc ?? 100) }

    var body: some View {
        SectionCard("Charging", symbol: "bolt.car.fill", tint: TessalyticsTheme.positive) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Battery to charge limit")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 12)
                        Text("\(Int(batteryLevel))% / \(Int(chargeLimit))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(batteryLevel, chargeLimit), total: max(chargeLimit, 1))
                        .tint(TessalyticsTheme.positive)
                }
                DetailRow(title: "State", value: status.chargingDetails?.chargingState ?? "Not reported")
                DetailRow(title: "Power", value: ValueFormatting.number(status.chargingDetails?.chargerPower, unit: "kW"))
                DetailRow(title: "Energy added", value: ValueFormatting.number(status.chargingDetails?.chargeEnergyAdded, unit: "kWh"))
                DetailRow(
                    title: "Time remaining",
                    value: status.chargingDetails?.timeToFullCharge.map { "\($0.formatted(.number.precision(.fractionLength(1)))) hr" } ?? "Not reported"
                )
            }
        }
    }
}

private struct VehicleActivityCard: View {
    let vehicle: Vehicle?

    var body: some View {
        SectionCard(
            "Synchronized history",
            symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            tint: TessalyticsTheme.neutral
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                CompactStat(title: "Drives", value: vehicle?.totalDrives?.formatted() ?? "—", tint: TessalyticsTheme.accent)
                CompactStat(title: "Charges", value: vehicle?.totalCharges?.formatted() ?? "—", tint: TessalyticsTheme.positive)
                CompactStat(title: "Updates", value: vehicle?.totalUpdates?.formatted() ?? "—", tint: TessalyticsTheme.steel)
            }
        }
    }
}

private struct VehicleSecurityCard: View {
    let status: VehicleStatus
    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

    var body: some View {
        SectionCard("Vehicle state", symbol: "lock.shield.fill", tint: TessalyticsTheme.neutral) {
            LazyVGrid(columns: columns, spacing: 10) {
                VehicleStateItem(title: "Locked", value: status.carStatus?.locked, symbol: "lock.fill")
                VehicleStateItem(title: "Sentry", value: status.carStatus?.sentryMode, symbol: "shield.fill")
                VehicleStateItem(title: "Doors", value: status.carStatus?.doorsOpen, symbol: "door.left.hand.open", healthyWhenFalse: true)
                VehicleStateItem(title: "Windows", value: status.carStatus?.windowsOpen, symbol: "rectangle.split.3x1", healthyWhenFalse: true)
                VehicleStateItem(title: "Trunk", value: status.carStatus?.trunkOpen, symbol: "car.rear", healthyWhenFalse: true)
                VehicleStateItem(title: "Frunk", value: status.carStatus?.frunkOpen, symbol: "car.front.waves.up", healthyWhenFalse: true)
            }
        }
    }
}

private struct VehicleStateItem: View {
    let title: String
    let value: Bool?
    let symbol: String
    var healthyWhenFalse = false

    private var isHealthy: Bool? { value.map { healthyWhenFalse ? !$0 : $0 } }
    private var stateText: String {
        guard let value else { return "Unavailable" }
        if healthyWhenFalse { return value ? "Open" : "Closed" }
        return value ? "On" : "Off"
    }
    private var tint: Color {
        guard let isHealthy else { return .secondary }
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
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(stateText)
    }
}

private struct TirePressureCard: View {
    let status: VehicleStatus

    var body: some View {
        SectionCard("Tire pressures", symbol: "gauge.with.dots.needle.50percent", tint: TessalyticsTheme.neutral) {
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    TireValue(title: "Front left", value: status.tpmsDetails?.tpmsPressureFl)
                    TireValue(title: "Front right", value: status.tpmsDetails?.tpmsPressureFr)
                }
                Divider().gridCellColumns(2)
                GridRow {
                    TireValue(title: "Rear left", value: status.tpmsDetails?.tpmsPressureRl)
                    TireValue(title: "Rear right", value: status.tpmsDetails?.tpmsPressureRr)
                }
            }
        }
    }
}

private struct TireValue: View {
    let title: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(ValueFormatting.number(value, unit: ""))
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct VehicleDetailsCard: View {
    let status: VehicleStatus

    var body: some View {
        SectionCard("Details", symbol: "info.circle.fill") {
            VStack(spacing: 12) {
                DetailRow(title: "Location", value: status.carGeodata?.geofence ?? "Not reported", symbol: "mappin.and.ellipse")
                DetailRow(title: "Software", value: status.carVersions?.version ?? "Not reported", symbol: "shippingbox.fill")
                DetailRow(title: "Logger", value: status.carStatus?.healthy == true ? "Healthy" : "Unavailable", symbol: "waveform.path.ecg")
            }
        }
    }
}
