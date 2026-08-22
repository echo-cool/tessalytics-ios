import Foundation

/// TeslaMateApi answers `/status` from the last vehicle poll. While a car is
/// asleep or offline it cannot read live telemetry, and its JSON encoder emits
/// Go zero values rather than nulls — `locked: false`, `est_battery_range: 0`,
/// `charge_limit_soc: 0`, `charging_state: ""`, every tyre at 0 psi.
///
/// Rendering those verbatim tells the owner that a locked car is unlocked and a
/// car at 80% has no range left, so every live reading is filtered through here
/// before it reaches a view.
enum TeslaModelNaming {
    private static let codes: Set<String> = ["S", "3", "X", "Y"]

    /// TeslaMate stores the model as a bare code ("3"), which reads as noise on
    /// its own. Expand the known ones to their marketing name.
    static func displayName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
        let upper = trimmed.uppercased()
        return codes.contains(upper) ? "Model \(upper)" : trimmed
    }
}

extension VehicleStatus {
    /// True when the car was awake at the last poll, so live telemetry can be
    /// trusted. Anything else means zero-valued fields are missing data, not
    /// measurements.
    var reportsLiveTelemetry: Bool {
        switch state?.lowercased() {
        case "online", "driving", "charging", "updating": true
        default: false
        }
    }

    /// How long the car has held its current state, when reported.
    var stateDuration: TimeInterval? {
        guard let since = stateSince?.value else { return nil }
        let elapsed = Date.now.timeIntervalSince(since)
        return elapsed > 60 ? elapsed : nil
    }
}

extension StatusBatteryDTO {
    /// The range figure worth showing, paired with a label that honestly says
    /// which one it is. `est_battery_range` collapses to zero while the car
    /// sleeps, so fall back to the rated and ideal figures TeslaMate retains.
    var displayRange: (value: Double, label: String)? {
        if let value = estBatteryRange, value > 0 { return (value, "estimated range") }
        if let value = ratedBatteryRange, value > 0 { return (value, "rated range") }
        if let value = idealBatteryRange, value > 0 { return (value, "ideal range") }
        return nil
    }

    var reportedUsableLevel: Int? { batteryLevel == nil ? nil : usableBatteryLevel }
}

extension StatusChargingDTO {
    var reportedState: String? { chargingState?.nilIfEmpty }
    /// A charge limit of zero is never a real setting.
    var reportedChargeLimit: Int? { (chargeLimitSoc ?? 0) > 0 ? chargeLimitSoc : nil }
    var reportedPower: Double? { (chargerPower ?? 0) > 0 ? chargerPower : nil }
    var reportedEnergyAdded: Double? { (chargeEnergyAdded ?? 0) > 0 ? chargeEnergyAdded : nil }
    var reportedTimeToFull: Double? { (timeToFullCharge ?? 0) > 0 ? timeToFullCharge : nil }
    var reportedVoltage: Int? { (chargerVoltage ?? 0) > 0 ? chargerVoltage : nil }
    var reportedCurrent: Double? { (chargerActualCurrent ?? 0) > 0 ? chargerActualCurrent : nil }
}

extension TPMSDTO {
    /// TeslaMate returns 0 psi for tyres it has no reading for.
    static func reported(_ value: Double?) -> Double? { (value ?? 0) > 0 ? value : nil }

    var hasAnyReading: Bool {
        [tpmsPressureFl, tpmsPressureFr, tpmsPressureRl, tpmsPressureRr]
            .contains { ($0 ?? 0) > 0 }
    }

    /// Whether the car has flagged any corner as soft. Its judgement, not a
    /// threshold this app invented — a right pressure for one wheel and load is
    /// a warning on another.
    var hasAnyWarning: Bool {
        [tpmsWarningFl, tpmsWarningFr, tpmsWarningRl, tpmsWarningRr].contains { $0 == true }
    }
}

extension CarVersionsDTO {
    var reportedVersion: String? { version?.nilIfEmpty }
    var reportedUpdateVersion: String? { updateVersion?.nilIfEmpty }
}

extension CarGeodataDTO {
    var reportedGeofence: String? { geofence?.nilIfEmpty }
}

extension TimeInterval {
    /// Compact "3h 35m" / "45m" phrasing for state ages.
    var elapsedDescription: String {
        let totalMinutes = Int((self / 60).rounded(.down))
        let days = totalMinutes / 1_440
        if days >= 1 {
            let hours = (totalMinutes % 1_440) / 60
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 1 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(max(minutes, 1))m"
    }
}

extension String {
    /// Uppercases only the first character, leaving the rest as authored.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension VehicleStatus {
    /// Whether the car is moving, or in gear ready to.
    ///
    /// `state` alone is not enough: TeslaMate reports "online" throughout a drive
    /// on some installs, and the shift position is what actually distinguishes a
    /// journey from a car sitting awake on a driveway.
    var isDriving: Bool {
        if state?.lowercased() == "driving" { return true }
        guard let shift = drivingDetails?.shiftState?.uppercased() else { return false }
        return ["D", "R", "N"].contains(shift)
    }

    /// Road speed, where a car that is driving and reports nothing is stopped.
    ///
    /// TeslaMate publishes `speed: null` rather than `0` while a car sits at a
    /// light, and the app rendered that as "Unavailable" — which claims the phone
    /// has lost the car, in the middle of a drive it is streaming. Standing still
    /// is a reading, and its value is zero.
    var liveSpeed: Double? {
        guard isDriving else { return drivingDetails?.speed }
        return drivingDetails?.speed ?? 0
    }

    /// Instantaneous pack power, on the same terms. Coasting draws nothing, and
    /// nothing is a number.
    var livePower: Double? {
        guard isDriving else { return drivingDetails?.power }
        return drivingDetails?.power ?? 0
    }
}

extension DrivingDetailsDTO {
    /// The gear, as a word, when it is one worth saying.
    ///
    /// Drive is not news while driving — the speed already says so. Reverse and
    /// neutral are, and a car sitting in neutral on a hill is worth a glance.
    var notableGear: String? {
        switch shiftState?.trimmingCharacters(in: .whitespaces).uppercased() {
        case "R": "Reversing"
        case "N": "In neutral"
        default: nil
        }
    }
}

/// A compass bearing, as a word.
enum CompassPoint {
    private static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// The eight-point name for a bearing in degrees, or nil when there is none.
    static func name(for degrees: Double?) -> String? {
        guard let degrees, degrees.isFinite else { return nil }
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalised < 0 ? normalised + 360 : normalised
        return names[Int((positive / 45).rounded()) % names.count]
    }
}

/// What is doing the driving, when the server says.
///
/// TeslaMate publishes nothing about autopilot, so most deployments will never
/// produce anything but `nil` here — and `nil` renders as no badge at all. A
/// forked broker that does publish it, or an Owner API session, gets the reading
/// shown for what it is: the name the car uses, not the app's guess.
enum SelfDrivingMode: Equatable, Sendable {
    /// The car is driving itself with the full package engaged.
    case fullSelfDriving
    /// Autosteer, TACC or another named aid short of FSD.
    case assisted(String)
    /// The server reports the system, and reports it as not engaged.
    case off

    /// The short word the badge shows.
    var label: String {
        switch self {
        case .fullSelfDriving: "FSD"
        case .assisted(let name): name
        case .off: "Manual"
        }
    }

    var symbol: String {
        switch self {
        case .fullSelfDriving: "car.top.lane.dashed.badge.steeringwheel"
        case .assisted: "steeringwheel"
        // Hands on the wheel is the picture of driving it yourself.
        case .off: "steeringwheel.and.hands"
        }
    }

    var isEngaged: Bool { self != .off }

    /// The full phrase, for VoiceOver and for the live readout.
    var accessibilityDescription: String {
        switch self {
        case .fullSelfDriving: "Full Self-Driving engaged"
        case .assisted(let name): "\(name) engaged"
        case .off: "Driving manually"
        }
    }
}

extension DrivingDetailsDTO {
    /// The names a car gives the full package, lowercased.
    private static let fullSelfDrivingNames: Set<String> = [
        "fsd", "full self driving", "full self-driving", "fullselfdriving",
        "fsd beta", "fsd supervised", "full self-driving (supervised)"
    ]
    /// The names that mean "reported, and not driving itself".
    private static let disengagedNames: Set<String> = ["off", "none", "unavailable", "disengaged", "manual", "standby"]

    /// What the server says is steering, or nil when it says nothing.
    ///
    /// A bare `isAutopilotEngaged` is enough on its own: a server that reports
    /// the flag without a name still knows more than the app does. The two
    /// disagree only when a stale name outlives a `false`, and the flag wins —
    /// claiming a car is driving itself when it is not is the worse mistake.
    var selfDrivingMode: SelfDrivingMode? {
        let name = autopilotState?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalised = name?.lowercased()

        if isAutopilotEngaged == false { return .off }
        if let normalised, Self.disengagedNames.contains(normalised) { return .off }

        if let normalised, Self.fullSelfDrivingNames.contains(normalised) { return .fullSelfDriving }
        if let name { return .assisted(name) }
        // No name at all, so the flag is the whole reading.
        guard isAutopilotEngaged == true else { return nil }
        return .fullSelfDriving
    }
}

extension VehicleStatus {
    /// Only worth reporting while the car is actually driving: a parked car's
    /// last autopilot reading describes a journey that has ended.
    var selfDrivingMode: SelfDrivingMode? {
        guard isDriving else { return nil }
        return drivingDetails?.selfDrivingMode
    }

    /// Whether this reading positively says the journey is over.
    ///
    /// Deliberately not the same question as `!isDriving`, which is also true of
    /// a reading that simply failed to mention it. A car parks by shifting into
    /// P, going to sleep or starting to charge — all statements. A reading that
    /// arrives with the driving block missing is a gap in what the car
    /// published, and ending the drive on one of those is what took the map out
    /// of the view tree mid-journey and put a black frame where it had been.
    var isPositivelyNotDriving: Bool {
        guard !isDriving else { return false }
        if drivingDetails?.shiftState?.trimmingCharacters(in: .whitespaces).uppercased() == "P" { return true }
        switch state?.lowercased() {
        case "asleep", "offline", "suspended", "parked", "charging", "updating": return true
        default: return false
        }
    }

    /// Whether the car is in a drive but standing still — at a light, in traffic,
    /// or waiting to turn.
    ///
    /// Distinct from parked: the drive has not ended, the charts keep running and
    /// the route stays on the map. It is only the speed that is zero.
    var isStoppedInDrive: Bool {
        guard isDriving else { return false }
        guard let speed = liveSpeed else { return false }
        return speed < 1
    }
}
