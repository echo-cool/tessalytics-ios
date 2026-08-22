import XCTest
@testable import Tessalytics

/// Regression tests for the sleeping-car payload.
///
/// The fixture below is the shape TeslaMateApi returns for a real car whose
/// `state` is `offline`: booleans and numbers it cannot read come back as Go
/// zero values rather than nulls. The app previously rendered them verbatim and
/// told the owner that a locked car was unlocked and a car at 80% charge had no
/// range left.
final class OfflineTelemetryTests: XCTestCase {
    private func decodeOfflineStatus() throws -> StatusDataDTO {
        let json = Data("""
        {
          "data": {
            "car": { "car_id": 1, "car_name": "Test Vehicle" },
            "status": {
              "display_name": "Test Vehicle",
              "state": "offline",
              "state_since": "2026-08-19T18:52:33-07:00",
              "odometer": 21066.633361170625,
              "car_status": {
                "healthy": true, "locked": false, "sentry_mode": false,
                "windows_open": false, "doors_open": false,
                "trunk_open": false, "frunk_open": false
              },
              "car_details": { "model": "3", "trim_badging": "74" },
              "car_geodata": { "geofence": "Home" },
              "car_versions": { "version": "2026.21.6", "update_available": false, "update_version": "" },
              "driving_details": { "shift_state": "", "power": 0, "speed": 0 },
              "climate_details": { "is_climate_on": false, "inside_temp": 37.9, "outside_temp": 23 },
              "battery_details": {
                "est_battery_range": 0,
                "rated_battery_range": 263.38060725363704,
                "ideal_battery_range": 263.38060725363704,
                "battery_level": 80,
                "usable_battery_level": 80
              },
              "charging_details": {
                "plugged_in": false, "charging_state": "", "charge_energy_added": 0,
                "charge_limit_soc": 0, "charger_power": 0, "charger_voltage": 0,
                "scheduled_charging_start_time": "0000-12-31T16:07:02-07:52",
                "time_to_full_charge": 0
              },
              "tpms_details": {
                "tpms_pressure_fl": 0, "tpms_pressure_fr": 0,
                "tpms_pressure_rl": 0, "tpms_pressure_rr": 0
              }
            },
            "units": { "unit_of_length": "mi", "unit_of_pressure": "psi", "unit_of_temperature": "C" }
          }
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Envelope<StatusDataDTO>.self, from: json).data
    }

    func testOfflineCarIsNotTreatedAsLiveTelemetry() throws {
        let status = try decodeOfflineStatus().status
        XCTAssertFalse(status.reportsLiveTelemetry)
    }

    func testRangeFallsBackToRatedWhenEstimateIsZero() throws {
        let status = try decodeOfflineStatus().status
        let range = try XCTUnwrap(status.batteryDetails?.displayRange)
        XCTAssertEqual(range.value, 263.38060725363704, accuracy: 0.0001)
        XCTAssertEqual(range.label, "rated range")
    }

    func testLockStateIsReportedAsUnknownWhileAsleep() throws {
        let payload = try decodeOfflineStatus()
        let summary = VehicleHeroSummary(status: payload.status, units: payload.units)
        XCTAssertEqual(summary.security.text, "Lock state unknown")
        XCTAssertFalse(summary.security.needsAttention)
        XCTAssertEqual(summary.stateNoun, "Offline")
        // A car is offline or asleep almost all the time, so the hero leads with
        // where it is rather than spending its loudest line on the least
        // surprising fact. The state noun stays for accessibility.
        XCTAssertFalse(summary.isNotable)
        // Where it is comes from a geocoded coordinate, and this summary was
        // built without one: the server's geofence is the last place a drive
        // ended inside one, which for a car parked anywhere else is an address
        // it left days ago.
        XCTAssertEqual(summary.headline, "Last seen")
        XCTAssertNil(summary.placeText)
        // The battery level itself survives the last poll and stays trustworthy.
        XCTAssertEqual(summary.batteryText, "80")
        // Two decimals: the server reports them, and rounding them off made a
        // range that was visibly falling look like one that was stuck.
        XCTAssertEqual(summary.rangeValue, "263.38")
    }

    func testAwakeCarStillReportsAnUnlockedDoorHonestly() throws {
        let payload = try decodeOfflineStatus()
        let awake = VehicleStatus(
            displayName: payload.status.displayName,
            state: "online",
            stateSince: payload.status.stateSince,
            odometer: payload.status.odometer,
            carStatus: payload.status.carStatus,
            carDetails: payload.status.carDetails,
            carGeodata: payload.status.carGeodata,
            carVersions: payload.status.carVersions,
            drivingDetails: payload.status.drivingDetails,
            climateDetails: payload.status.climateDetails,
            batteryDetails: payload.status.batteryDetails,
            chargingDetails: payload.status.chargingDetails,
            tpmsDetails: payload.status.tpmsDetails
        )
        XCTAssertTrue(awake.reportsLiveTelemetry)
        let summary = VehicleHeroSummary(status: awake, units: payload.units)
        XCTAssertEqual(summary.security.text, "Unlocked")
        XCTAssertTrue(summary.security.needsAttention)
    }

    func testZeroValuedChargingAndTyreFieldsAreTreatedAsMissing() throws {
        let status = try decodeOfflineStatus().status
        let charging = try XCTUnwrap(status.chargingDetails)
        XCTAssertNil(charging.reportedChargeLimit)
        XCTAssertNil(charging.reportedPower)
        XCTAssertNil(charging.reportedEnergyAdded)
        XCTAssertNil(charging.reportedTimeToFull)
        XCTAssertNil(charging.reportedState, "An empty charging_state string is not a state")

        let tpms = try XCTUnwrap(status.tpmsDetails)
        XCTAssertFalse(tpms.hasAnyReading)
        XCTAssertNil(TPMSDTO.reported(tpms.tpmsPressureFl))

        XCTAssertNil(status.carVersions?.reportedUpdateVersion, "An empty update_version is not an update")
        XCTAssertEqual(status.carVersions?.reportedVersion, "2026.21.6")
    }

    func testModelCodeIsExpandedToItsMarketingName() {
        XCTAssertEqual(TeslaModelNaming.displayName("3"), "Model 3")
        XCTAssertEqual(TeslaModelNaming.displayName("y"), "Model Y")
        XCTAssertEqual(TeslaModelNaming.displayName("Roadster"), "Roadster")
        XCTAssertNil(TeslaModelNaming.displayName(""))
        XCTAssertNil(TeslaModelNaming.displayName(nil))
    }

    func testElapsedDescriptionReadsAsAnAge() {
        XCTAssertEqual(TimeInterval(90).elapsedDescription, "1m")
        XCTAssertEqual(TimeInterval(3_600 * 3 + 60 * 38).elapsedDescription, "3h 38m")
        XCTAssertEqual(TimeInterval(3_600 * 2).elapsedDescription, "2h")
        XCTAssertEqual(TimeInterval(86_400 * 2 + 3_600 * 5).elapsedDescription, "2d 5h")
    }
}
