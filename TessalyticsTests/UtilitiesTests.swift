import XCTest
@testable import Tessalytics

final class UtilitiesTests: XCTestCase {
    func testRouteSimplificationPreservesEndpointsAndTurn() {
        let points = [CoordinateDTO(latitude: 0, longitude: 0), CoordinateDTO(latitude: 0, longitude: 0.5), CoordinateDTO(latitude: 0, longitude: 1), CoordinateDTO(latitude: 1, longitude: 1)]
        let simplified = RouteSimplifier.simplify(points, tolerance: 0.01)
        XCTAssertEqual(simplified.first, points.first); XCTAssertEqual(simplified.last, points.last)
        XCTAssertTrue(simplified.contains(points[2])); XCTAssertLessThan(simplified.count, points.count)
    }

    func testTrapezoidalIntegrationHandlesIrregularIntervalsAndGaps() throws {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [(start, 2.0), (start.addingTimeInterval(1800), 4.0), (start.addingTimeInterval(3600), 2.0)]
        XCTAssertEqual(try XCTUnwrap(AnalyticsService().integratedEnergy(samples: samples, maximumGap: 2000)), 3, accuracy: 0.0001)
        XCTAssertNil(AnalyticsService().integratedEnergy(samples: samples, maximumGap: 60))
    }

    func testSecretRedaction() {
        let output = SecretRedactor.redact("Authorization: Bearer abc token=xyz password=hunter2 ABCDEFGHJKLMNPRST 37.77490, -122.41940")
        XCTAssertFalse(output.contains("abc")); XCTAssertFalse(output.contains("xyz")); XCTAssertFalse(output.contains("hunter2")); XCTAssertFalse(output.contains("ABCDEFGH")); XCTAssertFalse(output.contains("37.77490"))
    }

    func testProfileValidation() throws {
        var draft = ProfileDraft(); draft.serverURL = "https://example.com///"
        XCTAssertEqual(try draft.profile().baseURL.absoluteString, "https://example.com")
        draft.serverURL = "http://example.com"; XCTAssertThrowsError(try draft.profile())
        draft.serverURL = "http://192.168.1.2"; draft.allowsLocalHTTP = true; XCTAssertNoThrow(try draft.profile())
    }

    func testAnalyticsDashboardBuildsSourceBackedChartsAndComparisons() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let samples = DemoAnalyticsFactory.samples(now: now, calendar: calendar)
        let window = AnalyticsTimeWindow.resolve(
            period: .thirtyDays,
            customStart: now.addingTimeInterval(-30 * 86_400),
            customEnd: now,
            now: now,
            calendar: calendar
        )

        let dashboard = AnalyticsDashboardBuilder(calendar: calendar).make(
            drives: samples.drives,
            charges: samples.charges,
            window: window
        )

        XCTAssertGreaterThan(dashboard.coverage.drives, 20)
        XCTAssertGreaterThanOrEqual(dashboard.coverage.charges, 12)
        XCTAssertEqual(dashboard.coverage.drives, dashboard.summary.driveCount)
        XCTAssertGreaterThan(dashboard.dailyDriving.count, 8)
        XCTAssertGreaterThan(dashboard.dailyCharging.count, 8)
        XCTAssertGreaterThanOrEqual(dashboard.chargeRelationships.count, 12)
        XCTAssertEqual(dashboard.weekdayActivity.count, 7)
        XCTAssertEqual(dashboard.timeOfDayMix.count, 4)
        XCTAssertNotNil(dashboard.previousSummary)
        XCTAssertGreaterThan(try XCTUnwrap(dashboard.summary.distance), 0)
        XCTAssertGreaterThan(try XCTUnwrap(dashboard.summary.chargingEnergy), 0)
    }

    func testAnalyticsCustomWindowUsesAnEqualPrecedingComparisonRange() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let end = start.addingTimeInterval(9 * 86_400)
        let window = AnalyticsTimeWindow.resolve(
            period: .custom,
            customStart: start,
            customEnd: end,
            now: end,
            calendar: calendar
        )

        let current = try XCTUnwrap(window.current)
        let previous = try XCTUnwrap(window.previous)
        XCTAssertEqual(current.upperBound.timeIntervalSince(current.lowerBound), previous.upperBound.timeIntervalSince(previous.lowerBound), accuracy: 0.001)
        XCTAssertEqual(previous.upperBound, current.lowerBound)
    }

    func testVehicleHeroPrioritizesParkedContextBatteryRangeAndSecurity() {
        let status = makeHeroStatus()
        let summary = VehicleHeroSummary(
            status: status,
            units: UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "C")
        )

        XCTAssertEqual(summary.activity, .parked)
        XCTAssertEqual(summary.headline, "Parked at Home")
        XCTAssertEqual(summary.batteryText, "78")
        XCTAssertEqual(summary.rangeValue, "238")
        XCTAssertEqual(summary.rangeLabel, "mi estimated range")
        XCTAssertEqual(summary.security.text, "Locked")
        XCTAssertEqual(summary.climateText, "Cabin 21.5°C")
        XCTAssertEqual(summary.locationText, "Home")
        XCTAssertNil(summary.charging)
    }

    func testVehicleHeroSurfacesChargingProgressAndETA() throws {
        let status = makeHeroStatus(
            batteryLevel: 45,
            pluggedIn: true,
            chargingState: "Charging",
            chargerPower: 7,
            timeToFullCharge: 1.5
        )
        let summary = VehicleHeroSummary(status: status, units: UnitsDTO(unitOfLength: "km", unitOfPressure: "bar", unitOfTemperature: "C"))

        XCTAssertEqual(summary.activity, .charging)
        XCTAssertEqual(summary.headline, "Charging · 7 kW")
        XCTAssertEqual(try XCTUnwrap(summary.charging).progress, 45.0 / 80.0, accuracy: 0.001)
        XCTAssertTrue(try XCTUnwrap(summary.charging).detail.contains("remaining"))
        XCTAssertEqual(try XCTUnwrap(summary.charging).limitText, "45% → 80%")
    }

    func testVehicleHeroPrioritizesDrivingSpeedAndOpenAccessWarning() {
        let status = makeHeroStatus(state: "driving", shiftState: "D", speed: 42, locked: false, doorsOpen: true)
        let summary = VehicleHeroSummary(status: status, units: UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F"))

        XCTAssertEqual(summary.activity, .driving)
        XCTAssertEqual(summary.headline, "Driving · 42 mph")
        XCTAssertEqual(summary.security.text, "Open access")
        XCTAssertTrue(summary.security.needsAttention)
        XCTAssertEqual(summary.climateText, "Cabin 21.5°F")
    }

    func testIntelligenceBuildsTransparentForecastsFromHistory() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let samples = DemoAnalyticsFactory.samples(now: now, calendar: calendar)
        let result = VehicleIntelligenceEngine(calendar: calendar).make(
            drives: samples.drives,
            charges: samples.charges,
            status: nil,
            distanceUnit: "km",
            now: now
        )

        XCTAssertEqual(result.forecasts.count, 4)
        XCTAssertEqual(result.distanceSeries.filter { $0.series == .observed }.count, 14)
        XCTAssertEqual(result.distanceSeries.filter { $0.series == .forecast }.count, 7)
        XCTAssertGreaterThan(try XCTUnwrap(result.forecasts.first { $0.kind == .weeklyDistance }?.value), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.forecasts.first { $0.kind == .monthlyChargingCost }?.value), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.forecasts.first { $0.kind == .typicalEfficiency }?.value), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.forecasts.first { $0.kind == .nextCharge }?.date), now)
        XCTAssertEqual(result.confidence, .high)
    }

    func testIntelligenceDetectsEfficiencyAndChargingCostChanges() {
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let drives = (0..<32).map { index in
            AnalyticsDriveSample(
                id: index,
                date: now.addingTimeInterval(Double(index - 31) * 86_400),
                distance: 20,
                durationMinutes: 35,
                energy: 4,
                efficiency: index >= 24 ? 210 : 150,
                destination: "Office"
            )
        }
        let charges = (0..<16).map { index in
            let isRecent = index >= 8
            let daysAgo = isRecent ? (15 - index) * 3 : 31 + (7 - index) * 3
            return AnalyticsChargeSample(
                id: index,
                date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                energy: 20,
                cost: isRecent ? 8 : 3,
                durationMinutes: 90,
                location: isRecent ? "Fast charger" : "Home"
            )
        }

        let result = VehicleIntelligenceEngine().make(
            drives: drives,
            charges: charges,
            status: nil,
            distanceUnit: "km",
            now: now
        )
        let IDs = Set(result.insights.map(\.id))
        XCTAssertTrue(IDs.contains("efficiency-change"))
        XCTAssertTrue(IDs.contains("charging-cost-change"))
        XCTAssertTrue(IDs.contains("charging-location-savings"))
    }

    func testNotificationPlannerCreatesStatusAndAnomalyAlerts() {
        let preferences = IntelligenceNotificationPreferences(
            enabled: true,
            lowBattery: true,
            chargeComplete: true,
            anomalies: true,
            softwareUpdates: true,
            lowBatteryThreshold: 20
        )
        let lowBatteryStatus = makeStatus(
            batteryLevel: 15,
            pluggedIn: false,
            chargingState: "Disconnected",
            timeToFullCharge: nil,
            updateAvailable: true
        )
        let planner = IntelligenceNotificationPlanner()
        let lowBattery = planner.statusNotifications(status: lowBatteryStatus, vehicleName: "Nova", preferences: preferences)
        XCTAssertEqual(Set(lowBattery.map(\.id)), ["tessalytics.low-battery", "tessalytics.software-update"])

        let chargingStatus = makeStatus(
            batteryLevel: 45,
            pluggedIn: true,
            chargingState: "Charging",
            timeToFullCharge: 1.5,
            updateAvailable: false
        )
        let charging = planner.statusNotifications(status: chargingStatus, vehicleName: "Nova", preferences: preferences)
        XCTAssertEqual(charging.map(\.id), ["tessalytics.charge-complete"])
        XCTAssertEqual(charging.first?.delay, 5_400)

        let insight = VehicleInsight(
            id: "efficiency-change",
            title: "Energy use is trending higher",
            message: "Recent consumption is elevated.",
            recommendation: "Check tire pressure.",
            symbol: "bolt.fill",
            severity: .warning
        )
        XCTAssertEqual(planner.insightNotifications(insights: [insight], vehicleName: "Nova", preferences: preferences).count, 1)
    }

    private func makeStatus(
        batteryLevel: Int,
        pluggedIn: Bool,
        chargingState: String,
        timeToFullCharge: Double?,
        updateAvailable: Bool
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Nova",
            state: "online",
            stateSince: nil,
            odometer: nil,
            carStatus: nil,
            carDetails: nil,
            carGeodata: nil,
            carVersions: CarVersionsDTO(version: "2026.20", updateAvailable: updateAvailable, updateVersion: "2026.24"),
            drivingDetails: nil,
            climateDetails: nil,
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: nil,
                ratedBatteryRange: nil,
                idealBatteryRange: nil,
                batteryLevel: batteryLevel,
                usableBatteryLevel: batteryLevel
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: pluggedIn,
                chargingState: chargingState,
                chargeEnergyAdded: nil,
                chargeLimitSoc: 80,
                chargePortDoorOpen: pluggedIn,
                chargerActualCurrent: nil,
                chargerPhases: nil,
                chargerPower: nil,
                chargerVoltage: nil,
                scheduledChargingStartTime: nil,
                timeToFullCharge: timeToFullCharge
            ),
            tpmsDetails: nil
        )
    }

    private func makeHeroStatus(
        state: String = "online",
        shiftState: String? = nil,
        speed: Double? = 0,
        batteryLevel: Int = 78,
        pluggedIn: Bool = false,
        chargingState: String = "Disconnected",
        chargerPower: Double? = 0,
        timeToFullCharge: Double? = nil,
        locked: Bool = true,
        doorsOpen: Bool = false
    ) -> VehicleStatus {
        VehicleStatus(
            displayName: "Nova",
            state: state,
            stateSince: nil,
            odometer: 18_642,
            carStatus: CarStatusDTO(
                healthy: true,
                locked: locked,
                sentryMode: false,
                windowsOpen: false,
                doorsOpen: doorsOpen,
                trunkOpen: false,
                frunkOpen: false
            ),
            carDetails: nil,
            carGeodata: CarGeodataDTO(geofence: "Home", location: nil),
            carVersions: nil,
            drivingDetails: DrivingDetailsDTO(shiftState: shiftState, power: 0, speed: speed, heading: nil, elevation: nil),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: false,
                insideTemp: 21.5,
                outsideTemp: 18,
                isPreconditioning: false,
                climateKeeperMode: "off"
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: 238,
                ratedBatteryRange: 229,
                idealBatteryRange: 245,
                batteryLevel: batteryLevel,
                usableBatteryLevel: batteryLevel
            ),
            chargingDetails: StatusChargingDTO(
                pluggedIn: pluggedIn,
                chargingState: chargingState,
                chargeEnergyAdded: 0,
                chargeLimitSoc: 80,
                chargePortDoorOpen: pluggedIn,
                chargerActualCurrent: nil,
                chargerPhases: nil,
                chargerPower: chargerPower,
                chargerVoltage: nil,
                scheduledChargingStartTime: nil,
                timeToFullCharge: timeToFullCharge
            ),
            tpmsDetails: nil
        )
    }
}
