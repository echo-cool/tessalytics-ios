import Foundation

/// The factory a car came out of.
///
/// The factory rather than the market, because that is what decides the pack: a
/// 2021 Long Range AWD Model 3 carries 82 kWh of Panasonic cells from Fremont and
/// 79 kWh of LG cells from Shanghai, and both were sold in Europe.
enum TeslaFactory: String, Codable, CaseIterable, Sendable {
    case fremont
    case austin
    case shanghai
    case berlin
    case lathrop

    var displayName: String {
        switch self {
        case .fremont: "Fremont, California"
        case .austin: "Austin, Texas"
        case .shanghai: "Shanghai"
        case .berlin: "Berlin-Brandenburg"
        case .lathrop: "Lathrop, California"
        }
    }
}

/// What a Tesla VIN says about the car, and nothing more.
///
/// Deliberately conservative. The VIN encodes the manufacturer, the model, the
/// model year and the plant, and those four are corroborated by two independent
/// fields each — the WMI and position 11 both name the plant, so a VIN that
/// disagrees with itself is rejected rather than guessed at. It does **not**
/// reliably encode the battery: published decoders disagree about what position 7
/// means, and this figure feeds every health and degradation number in the app,
/// so a field nobody agrees on is not one to read.
struct TeslaVIN: Equatable, Sendable {
    let vin: String
    /// The model letter: "3", "Y", "S", "X", "C" for Cybertruck, "R" for Roadster.
    let model: String
    let factory: TeslaFactory
    /// The model year from position 10. Not the production date — a car built in
    /// late 2023 can be a 2024 model year, which is why this narrows a pack
    /// lookup rather than deciding it.
    let modelYear: Int

    var isModel3: Bool { model == "3" }
    var isModelY: Bool { model == "Y" }
}

enum VINDecoder {
    /// Plants named by the first three characters.
    static let worldManufacturerIdentifiers: [String: TeslaFactory] = [
        "5YJ": .fremont,
        "7SA": .austin,
        "7G2": .lathrop,
        "LRW": .shanghai,
        "XP7": .berlin
    ]

    /// Plants named by position 11, which is the field that exists for exactly
    /// this purpose.
    static let plantCodes: [Character: TeslaFactory] = [
        "F": .fremont,
        "A": .austin,
        "B": .berlin,
        "C": .shanghai,
        "R": .shanghai,
        "K": .lathrop,
        "N": .fremont,
        "P": .fremont
    ]

    /// Position 10, on the ISO 3779 cycle that skips I, O, Q, U, Z and zero.
    static let modelYearCodes: [Character: Int] = [
        "F": 2015, "G": 2016, "H": 2017, "J": 2018, "K": 2019, "L": 2020,
        "M": 2021, "N": 2022, "P": 2023, "R": 2024, "S": 2025, "T": 2026,
        "V": 2027, "W": 2028, "X": 2029, "Y": 2030
    ]

    /// The model letters this app knows how to look a pack up for.
    static let knownModels: Set<String> = ["S", "3", "X", "Y", "C", "R"]

    /// Reads a VIN, or returns nil if it is not one this can trust.
    ///
    /// Every rejection here is deliberate. A VIN that fails its own check digit
    /// is a typo or a fabrication; a VIN whose WMI and plant code name different
    /// factories is one or the other misread. Either way the honest answer is "I
    /// cannot tell you", because the alternative is a confident pack capacity
    /// that silently rewrites the owner's degradation history.
    static func decode(_ raw: String?) -> TeslaVIN? {
        guard let normalised = normalise(raw), normalised.count == 17 else { return nil }
        let characters = Array(normalised)

        let wmi = String(characters[0..<3])
        guard let wmiFactory = worldManufacturerIdentifiers[wmi] else { return nil }
        guard isCheckDigitValid(characters) else { return nil }

        let model = String(characters[3])
        guard knownModels.contains(model) else { return nil }

        guard let modelYear = modelYearCodes[characters[9]] else { return nil }

        // Position 11 is the more specific of the two, but it only wins when the
        // WMI agrees. Tesla has built the same model at more than one plant under
        // one WMI, and a mismatch means this is not a VIN worth reading.
        guard let plantFactory = plantCodes[characters[10]] else { return nil }
        guard plantFactory == wmiFactory else { return nil }

        return TeslaVIN(vin: normalised, model: model, factory: plantFactory, modelYear: modelYear)
    }

    /// Uppercased and stripped of the separators people paste along with it.
    static func normalise(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The ISO 3779 check digit at position 9.
    ///
    /// Worth doing: it is the only part of a VIN that can tell a mistyped one from
    /// a real one, and this decoder is about to set a number that every health
    /// figure divides by.
    static func isCheckDigitValid(_ characters: [Character]) -> Bool {
        guard characters.count == 17 else { return false }
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (index, character) in characters.enumerated() {
            guard let value = transliterated(character) else { return false }
            sum += value * weights[index]
        }
        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return characters[8] == expected
    }

    /// The numeric value a VIN character carries for the check digit. I, O and Q
    /// are not valid in a VIN at all.
    static func transliterated(_ character: Character) -> Int? {
        if let digit = character.wholeNumberValue, character.isNumber { return digit }
        switch character {
        case "A", "J": return 1
        case "B", "K", "S": return 2
        case "C", "L", "T": return 3
        case "D", "M", "U": return 4
        case "E", "N", "V": return 5
        case "F", "W": return 6
        case "G", "P", "X": return 7
        case "H", "Y": return 8
        case "R", "Z": return 9
        default: return nil
        }
    }
}
