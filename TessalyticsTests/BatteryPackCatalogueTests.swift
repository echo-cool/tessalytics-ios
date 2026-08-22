import XCTest
@testable import Tessalytics

/// The VIN says the model, the factory and the model year. The shipped table says
/// what that combination left the factory with. Both feed the denominator of every
/// health figure in the app, so both are held to "answer or say you cannot".
final class VINDecoderTests: XCTestCase {
    /// Builds a VIN with a correct check digit, so the fixtures cannot drift out
    /// of agreement with the validator they are testing.
    private func vin(
        wmi: String,
        model: Character,
        year: Character,
        plant: Character,
        serial: String = "123456"
    ) -> String {
        // 1-3 WMI, 4 model, 5-8 attributes, 9 check digit, 10 year, 11 plant,
        // 12-17 serial. Seventeen, and the ninth is filled in below.
        var characters = Array("\(wmi)\(model)E1EA0\(year)\(plant)\(serial)")
        precondition(characters.count == 17, "A VIN fixture that is not 17 characters tests nothing")
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        let sum = characters.enumerated().reduce(0) { total, pair in
            total + (VINDecoder.transliterated(pair.element) ?? 0) * weights[pair.offset]
        }
        let remainder = sum % 11
        characters[8] = remainder == 10 ? "X" : Character(String(remainder))
        return String(characters)
    }

    func testAShanghaiModel3Decodes() throws {
        let decoded = try XCTUnwrap(VINDecoder.decode(vin(wmi: "LRW", model: "3", year: "P", plant: "C")))
        XCTAssertEqual(decoded.model, "3")
        XCTAssertEqual(decoded.factory, .shanghai)
        XCTAssertEqual(decoded.modelYear, 2023)
    }

    func testABerlinModelYDecodes() throws {
        let decoded = try XCTUnwrap(VINDecoder.decode(vin(wmi: "XP7", model: "Y", year: "R", plant: "B")))
        XCTAssertEqual(decoded.factory, .berlin)
        XCTAssertEqual(decoded.modelYear, 2024)
        XCTAssertTrue(decoded.isModelY)
    }

    func testAFremontModel3Decodes() throws {
        let decoded = try XCTUnwrap(VINDecoder.decode(vin(wmi: "5YJ", model: "3", year: "L", plant: "F")))
        XCTAssertEqual(decoded.factory, .fremont)
        XCTAssertEqual(decoded.modelYear, 2020)
    }

    func testPastedFormattingIsToleratedButLengthIsNot() throws {
        let plain = vin(wmi: "5YJ", model: "3", year: "L", plant: "F")
        let spaced = plain.enumerated().map { $0.offset % 5 == 0 ? " \($0.element)" : String($0.element) }.joined()
        XCTAssertEqual(VINDecoder.decode(spaced)?.vin, plain)
        XCTAssertNil(VINDecoder.decode(String(plain.dropLast())), "Sixteen characters is not a VIN")
    }

    func testAMistypedVINIsRejectedRatherThanDecoded() {
        // The check digit is the only thing that can tell a typo from a real VIN,
        // and this decoder is about to set a number every health figure divides by.
        var characters = Array(vin(wmi: "5YJ", model: "3", year: "L", plant: "F"))
        characters[8] = characters[8] == "0" ? "1" : "0"
        XCTAssertNil(VINDecoder.decode(String(characters)))
    }

    func testAVINThatDisagreesWithItselfIsRejected() {
        // A Shanghai WMI with a Fremont plant code is one or the other misread.
        XCTAssertNil(VINDecoder.decode(vin(wmi: "LRW", model: "3", year: "P", plant: "F")))
    }

    func testANonTeslaVINIsNotDecoded() {
        XCTAssertNil(VINDecoder.decode(vin(wmi: "WBA", model: "3", year: "P", plant: "F")))
        XCTAssertNil(VINDecoder.decode(nil))
        XCTAssertNil(VINDecoder.decode(""))
    }

    func testTheModelYearCycleMatchesTheStandard() {
        // ISO 3779 skips I, O, Q, U and Z.
        XCTAssertEqual(VINDecoder.modelYearCodes["L"], 2020)
        XCTAssertEqual(VINDecoder.modelYearCodes["N"], 2022)
        XCTAssertEqual(VINDecoder.modelYearCodes["S"], 2025)
        for skipped: Character in ["I", "O", "Q", "U", "Z"] {
            XCTAssertNil(VINDecoder.modelYearCodes[skipped], "\(skipped) is not a model-year code")
        }
    }
}

final class BatteryPackCatalogueTests: XCTestCase {
    private var catalogue: BatteryPackCatalogue!

    override func setUpWithError() throws {
        // The shipped resource, not a fixture: a table that fails to load or
        // parse is the failure mode worth catching here.
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: BatteryPackCatalogue.resourceName, withExtension: "json")
                ?? Bundle.main.url(forResource: BatteryPackCatalogue.resourceName, withExtension: "json")
        )
        catalogue = BatteryPackCatalogue(
            table: try JSONDecoder().decode(BatteryPackTable.self, from: try Data(contentsOf: url))
        )
    }

    private func decoded(model: String, factory: TeslaFactory, year: Int) -> TeslaVIN {
        TeslaVIN(vin: "TESTVIN", model: model, factory: factory, modelYear: year)
    }

    func testTheShippedTableLoadsAndIsSelfConsistent() throws {
        XCTAssertFalse(catalogue.table.entries.isEmpty)
        let codes = Set(catalogue.table.packs.map(\.code))
        for entry in catalogue.table.entries {
            XCTAssertTrue(codes.contains(entry.pack), "\(entry.pack) has no pack definition")
            XCTAssertNotNil(entry.range, "\(entry.model) \(entry.from)–\(entry.to) is not a quarter range")
        }
        XCTAssertTrue(catalogue.table.packs.allSatisfy { $0.capacityKWh > 0 })
    }

    /// The reason the table is keyed on the factory rather than the market: the
    /// same car, same year, different plant, different pack.
    func testTheFactoryDecidesThePack() {
        let fremont = catalogue.match(
            vin: decoded(model: "3", factory: .fremont, year: 2022), variant: .longRangeAWD
        )
        let shanghai = catalogue.match(
            vin: decoded(model: "3", factory: .shanghai, year: 2022), variant: .longRangeAWD
        )
        XCTAssertEqual(fremont.capacityKWh, 82, "Fremont built these with Panasonic cells")
        XCTAssertEqual(shanghai.capacityKWh, 79, "Shanghai built them with LG")
    }

    func testAStandardModel3FromShanghaiIsLFP() throws {
        let match = catalogue.match(
            vin: decoded(model: "3", factory: .shanghai, year: 2023), variant: .standard
        )
        let pack = try XCTUnwrap(match.candidates.first)
        XCTAssertEqual(pack.capacityKWh, 62)
        XCTAssertEqual(pack.chemistry, "LFP")
        XCTAssertFalse(match.isAmbiguous)
    }

    func testABerlinModelYStandardIsAmbiguousInTheYearTeslaUsedTwoSuppliers() {
        // 60 kWh BYD and 62 kWh CATL were both fitted. Two answers is the honest
        // output; picking one would be a coin flip that rewrites the owner's
        // degradation history.
        let match = catalogue.match(
            vin: decoded(model: "Y", factory: .berlin, year: 2023), variant: .standard
        )
        XCTAssertTrue(match.isAmbiguous)
        XCTAssertNil(match.capacityKWh, "An ambiguous match has no single answer")
        XCTAssertEqual(match.candidates.map(\.capacityKWh), [60, 62], "Ascending, and both offered")
    }

    func testTheCybertruckIsOnePackWhateverTheVariant() {
        for variant in [VehicleVariant.rearWheelDrive, .allWheelDrive, .cyberbeast] {
            let match = catalogue.match(vin: decoded(model: "C", factory: .austin, year: 2024), variant: variant)
            if variant == .rearWheelDrive {
                XCTAssertTrue(match.candidates.isEmpty, "RWD was not built in 2024")
            } else {
                XCTAssertEqual(match.capacityKWh, 123)
            }
        }
    }

    func testAModelYearIsMatchedAgainstTheQuartersItActuallySpans() {
        // A car built in late 2023 can be a 2024 model year, so the window reaches
        // back into the preceding Q4. The Model 3 Long Range RWD from Shanghai
        // started in 2023 Q4 and must be found by a 2024 VIN.
        let match = catalogue.match(
            vin: decoded(model: "3", factory: .shanghai, year: 2024), variant: .longRangeRWD
        )
        XCTAssertEqual(match.capacityKWh, 79)
    }

    func testACombinationTheTableDoesNotCoverAnswersNothing() {
        let match = catalogue.match(
            vin: decoded(model: "3", factory: .berlin, year: 2022), variant: .performance
        )
        XCTAssertTrue(match.candidates.isEmpty, "Berlin never built a Model 3")
        XCTAssertNil(match.capacityKWh)
    }

    func testAMissingResourceDegradesToAnEmptyTableRatherThanACrash() {
        let empty = BatteryPackCatalogue(
            table: BatteryPackTable(version: 0, revised: "", packs: [], entries: [])
        )
        let match = empty.match(vin: decoded(model: "3", factory: .fremont, year: 2022), variant: .longRangeAWD)
        XCTAssertTrue(match.candidates.isEmpty)
    }
}

final class VehicleVariantTests: XCTestCase {
    func testTeslaMateBadgesAreMappedWhereTheyAreUnambiguous() {
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "Long Range AWD", model: "3"), .longRangeAWD)
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "Performance", model: "3"), .performance)
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "P74D", model: "3"), .performance)
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "74D", model: "3"), .longRangeAWD)
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "Standard Range Plus", model: "3"), .standard)
        XCTAssertEqual(VehicleVariant.suggestion(fromTrim: "Cyberbeast", model: "C"), .cyberbeast)
    }

    func testAnAbsentOrUnrecognisedBadgeSuggestsNothing() {
        // Guessing "Performance" for a Long Range picks a pack that is wrong by
        // three kilowatt-hours and moves every health figure with it.
        XCTAssertNil(VehicleVariant.suggestion(fromTrim: nil, model: "3"))
        XCTAssertNil(VehicleVariant.suggestion(fromTrim: "   ", model: "3"))
        XCTAssertNil(VehicleVariant.suggestion(fromTrim: "62", model: "3"))
    }

    func testAModel3IsNotOfferedCybertruckVariants() {
        XCTAssertEqual(VehicleVariant.choices(forModel: "3"), [.standard, .longRangeRWD, .longRangeAWD, .performance])
        XCTAssertEqual(VehicleVariant.choices(forModel: "C"), [.rearWheelDrive, .allWheelDrive, .cyberbeast])
    }
}
