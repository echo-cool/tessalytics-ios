import Foundation

enum ValueFormatting {
    static func number(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard let value else { return "Unavailable" }
        let formatted = value.formatted(.number.precision(.fractionLength(0...digits)))
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
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
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
