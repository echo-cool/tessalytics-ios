import XCTest
@testable import Tessalytics

/// Tests for the fleet-wide figures the app derives itself.
///
/// TeslaMateApi has no aggregate endpoint, so these sums and models stand in for
/// the SQL the Grafana dashboards run. Where a number can be checked against the
/// real `/battery-health` response, it is.
@MainActor
final class FleetStatisticsTests: XCTestCase {
    private let serverID = UUID()
    private let carID = 1
    private let milesUnits = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "C")

    // MARK: - Fixtures

    private func drive(
        id: Int,
        distance: Double,
        odometerStart: Double,
        start: Date = .now,
        startLevel: Int? = nil,
        endLevel: Int? = nil,
        startRange: Double? = nil,
        endRange: Double? = nil
    ) -> DriveRecord {
        DriveRecord(
            serverID: serverID,
            carID: carID,
            dto: DriveSummaryDTO(
                driveId: id,
                startDate: FlexibleDate(start),
                endDate: FlexibleDate(start.addingTimeInterval(1_800)),
                startAddress: "A", endAddress: "B",
                odometerDetails: OdometerDetailsDTO(
                    odometerStart: odometerStart,
                    odometerEnd: odometerStart + distance,
                    odometerDistance: distance
                ),
                durationMin: 30, durationStr: nil, speedMax: nil, speedAvg: nil,
                powerMax: nil, powerMin: nil, outsideTempAvg: nil, insideTempAvg: nil,
                energyConsumedNet: nil, consumptionNet: nil,
                batteryDetails: LevelWindowDTO(
                    startBatteryLevel: startLevel, endBatteryLevel: endLevel,
                    startUsableBatteryLevel: nil, endUsableBatteryLevel: nil
                ),
                rangeRated: RangeWindowDTO(startRange: startRange, endRange: endRange, rangeDiff: nil),
                rangeIdeal: nil
            )
        )
    }

    private func charge(
        id: Int,
        added: Double?,
        used: Double?,
        cost: Double? = nil,
        odometer: Double? = nil,
        endRange: Double? = nil,
        endLevel: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        end: Date = .now
    ) -> ChargeRecord {
        ChargeRecord(
            serverID: serverID,
            carID: carID,
            dto: ChargeSummaryDTO(
                chargeId: id,
                startDate: FlexibleDate(end.addingTimeInterval(-3_600)),
                endDate: FlexibleDate(end),
                address: address,
                chargeEnergyAdded: added, chargeEnergyUsed: used, cost: cost,
                durationMin: 60, durationStr: nil, outsideTempAvg: nil,
                odometer: odometer, latitude: latitude, longitude: longitude,
                batteryDetails: LevelWindowDTO(
                    startBatteryLevel: 40, endBatteryLevel: endLevel,
                    startUsableBatteryLevel: nil, endUsableBatteryLevel: nil
                ),
                rangeRated: RangeWindowDTO(startRange: nil, endRange: endRange, rangeDiff: nil),
                rangeIdeal: nil
            )
        )
    }

    // MARK: - Drive stats

    func testLoggedDistanceSumsEveryDrive() {
        let statistics = FleetStatisticsBuilder.build(
            drives: [
                drive(id: 1, distance: 10, odometerStart: 1_000),
                drive(id: 2, distance: 25.5, odometerStart: 1_010)
            ],
            charges: [], batteryHealth: nil, odometer: 1_040, lastFullSync: .now, isComplete: true
        )
        XCTAssertEqual(statistics.drives.loggedDistance, 35.5, accuracy: 0.0001)
        XCTAssertEqual(statistics.drives.driveCount, 2)
        XCTAssertEqual(statistics.drives.firstLoggedOdometer, 1_000)
    }

    /// The gap is measured from the first logged drive, not from zero — mileage
    /// accumulated before the logger existed was never "lost".
    func testUnloggedDistanceMeasuresOnlyTheLoggingSpan() {
        let statistics = FleetStatisticsBuilder.build(
            drives: [
                drive(id: 1, distance: 10, odometerStart: 5_000),
                drive(id: 2, distance: 20, odometerStart: 5_020)
            ],
            charges: [], batteryHealth: nil, odometer: 5_050, lastFullSync: .now, isComplete: true
        )
        // Span 5,000 → 5,050 is 50; 30 was recorded, so 20 was not.
        XCTAssertEqual(statistics.drives.unloggedDistance ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(statistics.drives.coverage ?? -1, 0.6, accuracy: 0.0001)
    }

    func testUnloggedDistanceIsUnavailableWithoutAnOdometerReading() {
        let statistics = FleetStatisticsBuilder.build(
            drives: [drive(id: 1, distance: 10, odometerStart: 100)],
            charges: [], batteryHealth: nil, odometer: nil, lastFullSync: nil, isComplete: false
        )
        XCTAssertNil(statistics.drives.unloggedDistance)
        XCTAssertNil(statistics.drives.coverage)
        XCTAssertFalse(statistics.isComplete)
    }

    func testUnloggedDistanceNeverGoesNegative() {
        // A logger can record slightly more than the odometer span through
        // rounding; the shortfall must clamp rather than read as negative.
        let statistics = FleetStatisticsBuilder.build(
            drives: [drive(id: 1, distance: 60, odometerStart: 1_000)],
            charges: [], batteryHealth: nil, odometer: 1_050, lastFullSync: .now, isComplete: true
        )
        XCTAssertEqual(statistics.drives.unloggedDistance, 0)
        XCTAssertEqual(statistics.drives.coverage, 1)
    }

    // MARK: - Charging stats

    func testChargingTotalsCyclesAndEfficiency() {
        let statistics = FleetStatisticsBuilder.build(
            drives: [],
            charges: [
                charge(id: 1, added: 40, used: 44, cost: 8),
                charge(id: 2, added: 34.5, used: 38, cost: nil),
                charge(id: 3, added: 0, used: 0)
            ],
            batteryHealth: nil, odometer: nil, lastFullSync: .now, isComplete: true
        )
        XCTAssertEqual(statistics.charging.chargeCount, 3)
        XCTAssertEqual(statistics.charging.energyAdded, 74.5, accuracy: 0.0001)
        XCTAssertEqual(statistics.charging.energyUsed, 82, accuracy: 0.0001)
        XCTAssertEqual(statistics.charging.efficiency ?? 0, 74.5 / 82, accuracy: 0.0001)
        // One equivalent full charge per nominal pack.
        XCTAssertEqual(statistics.charging.cycles(capacityNew: 74.5) ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(statistics.charging.costTotal, 8, accuracy: 0.0001)
        XCTAssertEqual(statistics.charging.pricedChargeCount, 1)
    }

    func testChargingEfficiencyIsUnavailableWithoutDrawnEnergy() {
        let statistics = FleetStatisticsBuilder.build(
            drives: [], charges: [charge(id: 1, added: 20, used: nil)],
            batteryHealth: nil, odometer: nil, lastFullSync: nil, isComplete: false
        )
        XCTAssertNil(statistics.charging.efficiency)
        XCTAssertNil(statistics.charging.cycles(capacityNew: nil))
    }

    // MARK: - Battery health

    func testRangeAndCapacityLossDeriveFromTheBatteryHealthEndpoint() throws {
        // The real values this vehicle's /battery-health returns.
        let record = BatteryHealthRecord(
            serverID: serverID, carID: carID,
            dto: BatteryHealthDTO(
                maxRange: 337.171_019_699_431_64,
                currentRange: 330.152_604_989_391_4,
                maxCapacity: 74.287_733_333_333_34,
                currentCapacity: 72.348_107_786_960_51,
                ratedEfficiency: 13.6,
                batteryHealthPercentage: 97.389_036_575_298_89
            )
        )
        let statistics = FleetStatisticsBuilder.build(
            drives: [], charges: [], batteryHealth: record,
            odometer: nil, lastFullSync: nil, isComplete: false
        )
        let battery = try XCTUnwrap(statistics.battery)
        XCTAssertEqual(try XCTUnwrap(battery.rangeLost), 7.018_414_710_040_24, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(battery.capacityLost), 1.939_625_546_372_83, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(battery.rangeRetention), 0.979_183, accuracy: 0.0001)
        XCTAssertEqual(battery.ratedEfficiency, 13.6)
    }

    // MARK: - Capacity model

    /// Checked against a real charge: 272.51 mi rated range at 83%, with a rated
    /// efficiency of 13.6 kWh/100 km, models a ~71.9 kWh pack. The endpoint
    /// reports 72.35 kWh usable, so the model lands within a percent.
    func testCapacityIsModelledFromRangeAndLevelInMiles() {
        let observations = CapacityModel.observations(
            charges: [
                charge(id: 87, added: 20.52, used: 22.05, odometer: 21_058.9,
                       endRange: 272.508_550_067_603_44, endLevel: 83)
            ],
            ratedEfficiency: 13.6,
            units: milesUnits
        )
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0].capacity, 71.85, accuracy: 0.05)
        XCTAssertEqual(observations[0].odometer, 21_058.9)
        XCTAssertEqual(observations[0].chargeID, 87)
    }

    func testCapacityModelTreatsKilometreServersWithoutConversion() {
        let metric = CapacityModel.observations(
            charges: [charge(id: 1, added: 30, used: 32, odometer: 1_000, endRange: 438.5, endLevel: 83)],
            ratedEfficiency: 13.6,
            units: .metricDefaults
        )
        // Same underlying kilometres as the miles case above.
        XCTAssertEqual(metric[0].capacity, 71.85, accuracy: 0.05)
    }

    func testCapacityModelSkipsUnusableAndImplausibleRows() {
        let observations = CapacityModel.observations(
            charges: [
                charge(id: 1, added: 20, used: 21, odometer: nil, endRange: 250, endLevel: 80),
                charge(id: 2, added: 20, used: 21, odometer: 100, endRange: nil, endLevel: 80),
                charge(id: 3, added: 20, used: 21, odometer: 100, endRange: 250, endLevel: 0),
                // A trickle top-up moves the range too little to model from.
                charge(id: 4, added: 0.01, used: 0.02, odometer: 100, endRange: 250, endLevel: 80),
                // Implausible: would model a 900 kWh pack.
                charge(id: 5, added: 20, used: 21, odometer: 100, endRange: 4_000, endLevel: 10)
            ],
            ratedEfficiency: 13.6,
            units: milesUnits
        )
        XCTAssertTrue(observations.isEmpty, "Rows missing inputs or physically impossible must be dropped")
    }

    func testCapacityModelIsEmptyWithoutARatedEfficiency() {
        let observations = CapacityModel.observations(
            charges: [charge(id: 1, added: 20, used: 21, odometer: 100, endRange: 250, endLevel: 80)],
            ratedEfficiency: nil,
            units: milesUnits
        )
        XCTAssertTrue(observations.isEmpty)
    }

    func testObservationsAreOrderedByOdometer() {
        let observations = CapacityModel.observations(
            charges: [
                charge(id: 1, added: 20, used: 21, odometer: 9_000, endRange: 250, endLevel: 80),
                charge(id: 2, added: 20, used: 21, odometer: 1_000, endRange: 250, endLevel: 80),
                charge(id: 3, added: 20, used: 21, odometer: 5_000, endRange: 250, endLevel: 80)
            ],
            ratedEfficiency: 13.6, units: milesUnits
        )
        XCTAssertEqual(observations.map(\.odometer), [1_000, 5_000, 9_000])
    }

    func testMedianHandlesEvenAndOddCounts() {
        XCTAssertEqual(CapacityModel.median([3, 1, 2]), 2)
        XCTAssertEqual(CapacityModel.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(CapacityModel.median([]), 0)
    }

    /// Buckets are year-month plus a first/second-half-of-month marker, matching
    /// the TeslaMate median panel's grouping.
    func testSemiMonthlyMediansGroupByHalfMonth() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        let calendar = Calendar.current

        func date(day: Int) throws -> Date {
            components.day = day
            return try XCTUnwrap(calendar.date(from: components))
        }

        let observations = [
            CapacityObservation(id: 1, date: try date(day: 2), odometer: 1_000, capacity: 70),
            CapacityObservation(id: 2, date: try date(day: 12), odometer: 1_200, capacity: 74),
            CapacityObservation(id: 3, date: try date(day: 20), odometer: 2_000, capacity: 60),
            CapacityObservation(id: 4, date: try date(day: 28), odometer: 2_400, capacity: 62)
        ]
        let medians = CapacityModel.semiMonthlyMedians(observations)
        XCTAssertEqual(medians.count, 2)
        XCTAssertEqual(medians[0].capacity, 72, accuracy: 0.0001)
        XCTAssertEqual(medians[0].odometer, 1_100, accuracy: 0.0001)
        XCTAssertEqual(medians[1].capacity, 61, accuracy: 0.0001)
    }

    // MARK: - Charging sites

    func testSitesGroupByAddressAndShareSumsToOne() {
        let sites = ChargingSiteBuilder.sites(from: [
            charge(id: 1, added: 30, used: 32, odometer: 1, endRange: nil, endLevel: nil,
                   latitude: 37.0, longitude: -121.0, address: "Home"),
            charge(id: 2, added: 10, used: 11, odometer: 2, endRange: nil, endLevel: nil,
                   latitude: 37.2, longitude: -121.2, address: "Home"),
            charge(id: 3, added: 60, used: 64, odometer: 3, endRange: nil, endLevel: nil,
                   latitude: 38.0, longitude: -122.0, address: "Supercharger")
        ])
        XCTAssertEqual(sites.count, 2)
        // Ordered by energy, so the supercharger leads.
        XCTAssertEqual(sites[0].name, "Supercharger")
        XCTAssertEqual(sites[0].share, 0.6, accuracy: 0.0001)
        XCTAssertEqual(sites[1].name, "Home")
        XCTAssertEqual(sites[1].energyAdded, 40, accuracy: 0.0001)
        XCTAssertEqual(sites[1].sessions, 2)
        // Centroid of the two home sessions.
        XCTAssertEqual(sites[1].latitude, 37.1, accuracy: 0.0001)
        XCTAssertEqual(sites.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testSitesIgnoreChargesWithoutCoordinatesOrEnergy() {
        let sites = ChargingSiteBuilder.sites(from: [
            charge(id: 1, added: 30, used: 32, address: "No position"),
            charge(id: 2, added: 0, used: 0, latitude: 37, longitude: -121, address: "No energy")
        ])
        XCTAssertTrue(sites.isEmpty)
    }

    // MARK: - Projected range

    func testProjectedRangeExtrapolatesToAFullCharge() {
        let day = Date(timeIntervalSince1970: 1_772_000_000)
        let points = ProjectedRangeModel.points(
            drives: [
                drive(id: 1, distance: 10, odometerStart: 100, start: day,
                      startLevel: 80, endLevel: 70, startRange: 240, endRange: 210)
            ],
            charges: [],
            interval: .weekOfYear
        )
        XCTAssertEqual(points.count, 1)
        // Ranges and levels are summed before dividing, weighting the fuller
        // reading more heavily: (240 + 210) / (80 + 70) * 100 = 300.
        XCTAssertEqual(points[0].projectedRange, 300, accuracy: 0.0001)
    }

    func testProjectedRangeIgnoresSamplesWithoutRangeOrLevel() {
        let points = ProjectedRangeModel.points(
            drives: [drive(id: 1, distance: 10, odometerStart: 100, startLevel: nil, endLevel: nil)],
            charges: [charge(id: 1, added: 10, used: 11, endRange: nil, endLevel: nil)],
            interval: .weekOfYear
        )
        XCTAssertTrue(points.isEmpty)
    }
}
