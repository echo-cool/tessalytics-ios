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
