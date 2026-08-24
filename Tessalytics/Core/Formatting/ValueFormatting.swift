import Foundation

enum ValueFormatting {
    static func number(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard let value else { return "Unavailable" }
        let formatted = value.formatted(.number.precision(.fractionLength(0...digits)))
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    static func distance(_ value: Double?, units: UnitsDTO?, digits: Int = 1) -> String {
        let units = units ?? .metricDefaults
        // Converted first: the server sends values in the car's units, and the
        // owner may have asked to read something else.
        return number(units.displayDistance(value), unit: units.lengthSymbol, digits: digits)
    }

    static func speed(_ value: Double?, units: UnitsDTO?, digits: Int = 1) -> String {
        let units = units ?? .metricDefaults
        // Converted first: the server sends values in the car's units, and the
        // owner may have asked to read something else.
        return number(units.displaySpeed(value), unit: units.speedSymbol, digits: digits)
    }

    static func temperature(_ value: Double?, units: UnitsDTO?, digits: Int = 1) -> String {
        let units = units ?? .metricDefaults
        // Converted first: the server sends values in the car's units, and the
        // owner may have asked to read something else.
        return number(units.displayTemperature(value), unit: units.temperatureSymbol, digits: digits)
    }

    static func pressure(_ value: Double?, units: UnitsDTO?, digits: Int = 1) -> String {
        let units = units ?? .metricDefaults
        // Converted first: the server sends values in the car's units, and the
        // owner may have asked to read something else.
        return number(units.displayPressure(value), unit: units.pressureSymbol, digits: digits)
    }

    static func efficiency(_ value: Double?, units: UnitsDTO?, digits: Int = 1) -> String {
        let units = units ?? .metricDefaults
        // Converted first: the server sends values in the car's units, and the
        // owner may have asked to read something else.
        return number(units.displayEfficiency(value), unit: units.efficiencySymbol, digits: digits)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Not reported" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func duration(minutes: Int?) -> String {
        guard let minutes else { return "Unavailable" }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
    static func currency(_ value: Double?, code: String = Locale.current.currency?.identifier ?? "USD") -> String {
        guard let value else { return "No cost configured" }
        return value.formatted(.currency(code: code))
    }

    /// Energy, promoted to MWh once kilowatt-hours stop being readable.
    ///
    /// A lifetime charging total runs to thousands of kWh, and "4,182 kWh" is
    /// harder to read at a glance than "4.18 MWh".
    static func energy(_ kilowattHours: Double?, digits: Int = 1) -> String {
        guard let kilowattHours else { return "Unavailable" }
        if abs(kilowattHours) >= 1_000 {
            let megawattHours = kilowattHours / 1_000
            return "\(megawattHours.formatted(.number.precision(.fractionLength(0...2)))) MWh"
        }
        return number(kilowattHours, unit: "kWh", digits: digits)
    }

    /// A 0...1 ratio as a percentage.
    static func percentage(_ ratio: Double?, digits: Int = 1) -> String {
        guard let ratio else { return "Unavailable" }
        return ratio.formatted(.percent.precision(.fractionLength(0...digits)))
    }

    /// Charging cost, where exactly zero means TeslaMate has no tariff for the
    /// session rather than that the electricity was free. Rendering a column of
    /// "$0.00" tells the owner nothing, so absent pricing says so.
    static func chargeCost(_ value: Double?) -> String {
        guard let value, value > 0 else { return "No cost data" }
        return currency(value)
    }

    /// The clock time a reading arrived, to the second.
    ///
    /// Absolute rather than "updated just now". Relative wording cannot say
    /// whether a live reading is a quarter of a second or nine seconds old, which
    /// is the only question worth asking of a stream — and it reads as current
    /// right up to the minute mark, including when nothing is arriving at all.
    static func readingTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .standard)
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
