import Foundation

/// A drive that keeps going, so live mode can be watched rather than imagined.
///
/// `DemoExperience.drivingStatus` freezes one instant of a journey, which is
/// enough for a screenshot and not nearly enough for anything else: a map that
/// never moves cannot show a map that flickers while it moves, a speed that is
/// always 63 mph cannot show what the screen says at a red light, and a route
/// that never grows cannot show a route redrawn once a second.
///
/// So this advances. It is a plain value with one `mutating` step, deterministic
/// from its own state and the size of the step — no clock, no randomness — which
/// is what lets a test walk it forward a minute in a millisecond and assert on
/// exactly the reading a driver would have been looking at.
struct DemoDriveSimulation: Equatable, Sendable {
    /// The cycle the drive repeats, in seconds. Long enough to be a stretch of
    /// road, short enough that a test does not have to wait for one.
    static let cycle: TimeInterval = 120
    /// How often TeslaMate publishes while a car is moving.
    static let publishInterval: TimeInterval = 0.4

    /// Where the demo drive starts: the same corner of Mountain View the seeded
    /// history uses, so the live route joins the drawn one.
    static let origin = CoordinateDTO(latitude: 37.3861, longitude: -122.0839)

    private(set) var elapsed: TimeInterval = 0
    private(set) var latitude = origin.latitude
    private(set) var longitude = origin.longitude
    private(set) var odometer: Double = 18_642
    private(set) var heading: Double = 42
    /// Kilometres travelled, which the battery drains against.
    private(set) var distance: Double = 0
    /// Publishes every third reading without a position.
    ///
    /// A fault worth being able to produce on demand. A gap like this used to
    /// take the map out of the view tree for a frame, and a `Map` that leaves
    /// the tree comes back as an empty map surface — the flash the hero card had
    /// several times a minute. The UI test that holds that fixed needs a way to
    /// make the gap happen.
    var dropsPositions = false

    init(from coordinate: CoordinateDTO = origin, odometer: Double = 18_642, dropsPositions: Bool = false) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.odometer = odometer
        self.dropsPositions = dropsPositions
    }

    /// Whether the reading at this point in the drive carries a position.
    var reportsPosition: Bool {
        guard dropsPositions else { return true }
        return Int((elapsed / Self.publishInterval).rounded()) % 3 != 0
    }

    /// Metres per degree of latitude. Near enough anywhere a demo drives.
    private static let metresPerDegreeLatitude = 111_320.0

    /// The speed profile, in km/h, as a function of where in the cycle we are.
    ///
    /// One acceleration, one deliberate stop at a light, and a cruise. The stop
    /// is the reason the profile exists: a car standing still in the middle of a
    /// drive is a state the screen has to have something to say about, and it is
    /// otherwise the hardest one to be looking at when it happens.
    static func speed(atCyclePosition position: TimeInterval) -> Double {
        switch position {
        case ..<18:
            // Pulling away.
            60 * (position / 18)
        case ..<26:
            // Braking for the light.
            60 * (1 - (position - 18) / 8)
        case ..<44:
            // Stopped at it. This is the "waiting at a red light" case.
            0
        case ..<58:
            72 * ((position - 44) / 14)
        default:
            // Cruising, with the small variation a real road has.
            72 + sin((position - 58) / 9) * 7
        }
    }

    /// What is steering, as a function of the cycle.
    ///
    /// Both answers appear in every cycle on purpose: a badge that is always on
    /// is indistinguishable from a badge that is stuck on.
    static func autopilot(atCyclePosition position: TimeInterval) -> (state: String, engaged: Bool) {
        position >= 58 ? ("Full Self-Driving", true) : ("off", false)
    }

    var cyclePosition: TimeInterval { elapsed.truncatingRemainder(dividingBy: Self.cycle) }
    var speed: Double { Self.speed(atCyclePosition: cyclePosition) }
    var isStopped: Bool { speed < 0.5 }

    /// Moves the drive on, and answers with the reading a car would have
    /// published at the end of the step.
    mutating func advance(by step: TimeInterval, now: Date = .now) -> VehicleStatus {
        elapsed += step
        let kilometresPerHour = speed
        let kilometres = kilometresPerHour / 3_600 * step
        distance += kilometres
        odometer += kilometres

        // A long, lazy right-hand curve, so the route on the map is a road rather
        // than a ruler line. Only turning while moving: a stationary car that
        // keeps rotating its arrow looks broken.
        if kilometres > 0 {
            heading = (heading + kilometres * 26).truncatingRemainder(dividingBy: 360)
        }
        let radians = heading * .pi / 180
        let metres = kilometres * 1_000
        latitude += metres * cos(radians) / Self.metresPerDegreeLatitude
        longitude += metres * sin(radians)
            / (Self.metresPerDegreeLatitude * cos(latitude * .pi / 180))

        return status(now: now)
    }

    /// Power tracks the speed profile: drawing while accelerating, regenerating
    /// while slowing, nothing at all while stopped.
    var power: Double {
        guard !isStopped else { return 0 }
        let ahead = Self.speed(atCyclePosition: (cyclePosition + 1).truncatingRemainder(dividingBy: Self.cycle))
        let acceleration = ahead - speed
        return (speed * 0.28 + acceleration * 9).rounded()
    }

    func status(now: Date = .now) -> VehicleStatus {
        let assistance = Self.autopilot(atCyclePosition: cyclePosition)
        // Roughly a quarter of a percent per kilometre, which is about right for
        // a Long Range.
        let level = max(12, 78 - distance * 0.55)
        return VehicleStatus(
            displayName: "Aurora",
            state: "driving",
            stateSince: FlexibleDate(now.addingTimeInterval(-elapsed)),
            odometer: odometer,
            carStatus: CarStatusDTO(
                healthy: true,
                locked: true,
                sentryMode: false,
                windowsOpen: false,
                doorsOpen: false,
                trunkOpen: false,
                frunkOpen: false
            ),
            carDetails: CarDetailsDTO(model: "Model Y", trimBadging: "Long Range", efficiency: 0.158),
            carGeodata: CarGeodataDTO(
                // No geofence: a car on a road is not standing in one, and the
                // address under the headline is resolved from the coordinate.
                geofence: nil,
                location: reportsPosition ? CoordinateDTO(latitude: latitude, longitude: longitude) : nil
            ),
            carVersions: CarVersionsDTO(version: "2026.20.3", updateAvailable: false, updateVersion: nil),
            drivingDetails: DrivingDetailsDTO(
                shiftState: "D",
                power: power,
                speed: speed,
                heading: heading,
                elevation: 28 + sin(elapsed / 40) * 34,
                autopilotState: assistance.state,
                isAutopilotEngaged: assistance.engaged
            ),
            climateDetails: ClimateDetailsDTO(
                isClimateOn: true,
                insideTemp: 21.5,
                outsideTemp: 18,
                isPreconditioning: false,
                climateKeeperMode: nil
            ),
            batteryDetails: StatusBatteryDTO(
                estBatteryRange: (level * 3.05).rounded(),
                ratedBatteryRange: (level * 3.05).rounded(),
                idealBatteryRange: (level * 3.2).rounded(),
                batteryLevel: Int(level.rounded()),
                usableBatteryLevel: Int(level.rounded()) - 1
            ),
            chargingDetails: nil,
            tpmsDetails: TPMSDTO(
                tpmsPressureFl: 42.1,
                tpmsPressureFr: 42.1,
                tpmsPressureRl: 42.4,
                tpmsPressureRr: 41.7
            )
        )
    }
}
