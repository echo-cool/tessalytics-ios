import Foundation

/// A variant, in the terms the pack table is written in.
enum VehicleVariant: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case longRangeRWD
    case longRangeAWD
    case performance
    case rearWheelDrive
    case allWheelDrive
    case cyberbeast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .longRangeRWD: "Long Range RWD"
        case .longRangeAWD: "Long Range AWD"
        case .performance: "Performance"
        case .rearWheelDrive: "RWD"
        case .allWheelDrive: "AWD"
        case .cyberbeast: "Cyberbeast"
        }
    }

    /// The variants worth offering for a model, so a Model 3 is not asked whether
    /// it is a Cyberbeast.
    static func choices(forModel model: String) -> [VehicleVariant] {
        model == "C"
            ? [.rearWheelDrive, .allWheelDrive, .cyberbeast]
            : [.standard, .longRangeRWD, .longRangeAWD, .performance]
    }

    /// A best guess from what TeslaMate calls the trim, which is not a controlled
    /// vocabulary — it is whatever the car reported, and it is frequently absent.
    ///
    /// Only ever a *suggestion* for a control the owner can change: guessing
    /// "Performance" for a Long Range would pick a pack that is wrong by 3 kWh
    /// and quietly move every health figure with it.
    static func suggestion(fromTrim trim: String?, model: String) -> VehicleVariant? {
        guard let text = trim?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        if model == "C" {
            if text.contains("beast") { return .cyberbeast }
            if text.contains("awd") || text.contains("dual") { return .allWheelDrive }
            if text.contains("rwd") || text.contains("rear") { return .rearWheelDrive }
            return nil
        }
        // TeslaMate reports badges like "74D" and "P74D" as well as words.
        if text.hasPrefix("p") && text.contains("d") { return .performance }
        if text.contains("performance") { return .performance }
        if text.contains("long range") || text.contains("lr") {
            if text.contains("awd") || text.contains("dual") { return .longRangeAWD }
            if text.contains("rwd") || text.contains("rear") { return .longRangeRWD }
            return .longRangeAWD
        }
        if text.hasSuffix("d") { return .longRangeAWD }
        if text.contains("standard") || text.contains("sr") { return .standard }
        return nil
    }
}

/// A production quarter, which is how the pack table is indexed.
struct ProductionQuarter: Codable, Equatable, Comparable, Sendable {
    let year: Int
    /// 1 through 4.
    let quarter: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.quarter) < (rhs.year, rhs.quarter)
    }

    /// Parses "2024-Q3".
    init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), parts[1].hasPrefix("Q"),
              let quarter = Int(parts[1].dropFirst()), (1...4).contains(quarter) else { return nil }
        self.year = year
        self.quarter = quarter
    }

    init(year: Int, quarter: Int) {
        self.year = year
        self.quarter = max(1, min(4, quarter))
    }

    init(date: Date, calendar: Calendar = .current) {
        let month = calendar.component(.month, from: date)
        self.init(year: calendar.component(.year, from: date), quarter: (month - 1) / 3 + 1)
    }
}

/// One pack the table knows about.
struct BatteryPack: Codable, Equatable, Sendable {
    let code: String
    let capacityKWh: Double
    let cell: String
    let chemistry: String
}

/// The shipped table.
struct BatteryPackTable: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let model: String
        let variant: VehicleVariant
        let factory: TeslaFactory
        let from: String
        let to: String
        let pack: String

        var range: ClosedRange<ProductionQuarter>? {
            guard let start = ProductionQuarter(from), let end = ProductionQuarter(to), start <= end else {
                return nil
            }
            return start...end
        }
    }

    let version: Int
    let revised: String
    let packs: [BatteryPack]
    let entries: [Entry]
}

/// What the table can say about one car.
struct BatteryPackMatch: Equatable, Sendable {
    /// Every distinct capacity the table allows for this car, ascending.
    let candidates: [BatteryPack]
    let factory: TeslaFactory
    let variant: VehicleVariant
    let modelYear: Int

    /// The one answer, when the table gives exactly one.
    var capacityKWh: Double? { candidates.count == 1 ? candidates[0].capacityKWh : nil }
    /// More than one pack was built for this car in this year, so the table alone
    /// cannot say which is in it.
    var isAmbiguous: Bool { candidates.count > 1 }
}

/// Looks up what a car left the factory with.
///
/// The table ships in the app rather than coming from a server. Two reasons. The
/// app talks to any TeslaMate backend, including TeslaMateApi, and a table held by
/// one of them would leave everyone else without it. And this figure is the
/// denominator of every health calculation, which the app is expected to produce
/// offline — a number that needs the network to exist is a number that disappears
/// in a garage.
struct BatteryPackCatalogue: Sendable {
    let table: BatteryPackTable

    static let resourceName = "battery-packs"

    /// The shipped table, or an empty one if the resource is missing — a bundled
    /// file that failed to load is a build mistake, not a reason to crash a car
    /// app on a motorway.
    static let shipped: BatteryPackCatalogue = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(BatteryPackTable.self, from: data) else {
            return BatteryPackCatalogue(
                table: BatteryPackTable(version: 0, revised: "", packs: [], entries: [])
            )
        }
        return BatteryPackCatalogue(table: table)
    }()

    private func pack(code: String) -> BatteryPack? { table.packs.first { $0.code == code } }

    /// The packs the table allows for a decoded VIN and a variant.
    ///
    /// A model year is a range of quarters, not a point, and Tesla's model years
    /// run ahead of the calendar — a car built in late 2023 can be a 2024. So the
    /// lookup asks which packs were fitted to that model, variant and factory at
    /// any point from the last quarter of the preceding year through the model
    /// year itself, and reports every distinct answer rather than picking one.
    func match(vin: TeslaVIN, variant: VehicleVariant) -> BatteryPackMatch {
        let window = ProductionQuarter(year: vin.modelYear - 1, quarter: 4)...ProductionQuarter(
            year: vin.modelYear, quarter: 4
        )
        let codes = table.entries
            .filter { $0.model == vin.model && $0.variant == variant && $0.factory == vin.factory }
            .compactMap { entry -> [String]? in
                guard let range = entry.range, range.overlaps(window) else { return nil }
                return [entry.pack]
            }
            .flatMap { $0 }

        var seen = Set<String>()
        let candidates = codes
            .filter { seen.insert($0).inserted }
            .compactMap(pack(code:))
            .sorted { $0.capacityKWh < $1.capacityKWh }

        return BatteryPackMatch(
            candidates: candidates,
            factory: vin.factory,
            variant: variant,
            modelYear: vin.modelYear
        )
    }
}

private extension ClosedRange where Bound == ProductionQuarter {
    func overlaps(_ other: ClosedRange<ProductionQuarter>) -> Bool {
        lowerBound <= other.upperBound && other.lowerBound <= upperBound
    }
}
