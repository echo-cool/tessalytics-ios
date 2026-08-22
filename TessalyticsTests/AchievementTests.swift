import SwiftData
import XCTest
@testable import Tessalytics

/// Achievements are facts about the car, computed on the device. Game Center is
/// where they are recorded, not where they come from — so the arithmetic has to
/// stand on its own, and these are that arithmetic.
final class AchievementTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private lazy var start = Date(timeIntervalSince1970: 1_780_000_000)

    private func progress(_ achievement: Achievement, _ facts: AchievementFacts) -> AchievementProgress {
        AchievementProgress(achievement: achievement, value: AchievementCatalogue.value(of: achievement, from: facts))
    }

    func testEveryIdentifierIsUniqueAndNamespaced() {
        // Game Center keys a player's progress on this string forever. A
        // duplicate would have two achievements overwriting each other.
        let ids = AchievementCatalogue.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Two achievements share an identifier")
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix(AchievementCatalogue.prefix) })
        XCTAssertTrue(AchievementCatalogue.all.allSatisfy { $0.target > 0 }, "A zero target is always complete")
    }

    func testProgressIsAPercentageAndNeverOverruns() {
        var facts = AchievementFacts()
        facts.distanceKilometres = 25_000
        let entry = progress(AchievementCatalogue.thousandKilometres, facts)
        XCTAssertTrue(entry.isEarned)
        XCTAssertEqual(entry.percentComplete, 100, "Twenty-five times over is still 100%")

        facts.distanceKilometres = 250
        XCTAssertEqual(progress(AchievementCatalogue.thousandKilometres, facts).percentComplete, 25, accuracy: 0.001)
    }

    func testDistanceTargetsDoNotMoveWithTheOwnersUnits() {
        // The facts builder converts to kilometres, so a car that has driven
        // 1,000 km has earned it whether the server reports km or miles.
        let metric = AchievementFactsBuilder.build(
            drives: [], charges: [], battery: nil, placesVisited: 0, softwareVersions: 0,
            units: UnitsDTO(unitOfLength: "km", unitOfPressure: "bar", unitOfTemperature: "C")
        )
        XCTAssertEqual(metric.distanceKilometres, 0)
        XCTAssertEqual(AchievementFactsBuilder.kilometreFactor(for: .metricDefaults), 1)
        XCTAssertEqual(
            AchievementFactsBuilder.kilometreFactor(
                for: UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")
            ),
            1.609_344,
            accuracy: 0.000_001
        )
    }

    func testTheWellKeptAwardNeedsBothHalvesOfIt() {
        // 90% health at 200 km is not an achievement, it is a new car.
        var facts = AchievementFacts()
        facts.batteryHealthPercent = 97
        facts.distanceKilometres = 200
        XCTAssertFalse(progress(AchievementCatalogue.wellKept, facts).isEarned)

        facts.distanceKilometres = 60_000
        XCTAssertTrue(progress(AchievementCatalogue.wellKept, facts).isEarned)

        facts.batteryHealthPercent = 85
        XCTAssertFalse(progress(AchievementCatalogue.wellKept, facts).isEarned)

        facts.batteryHealthPercent = nil
        XCTAssertFalse(progress(AchievementCatalogue.wellKept, facts).isEarned, "Unknown health earns nothing")
    }

    func testARequirementIsWrittenInTheUnitsTheProgressIsWrittenIn() {
        // The screen read "Complete a single drive of 300 km" directly above
        // "96 of 186 mi", which is two different targets as far as a reader is
        // concerned.
        let imperial = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")
        XCTAssertEqual(
            AchievementCatalogue.longDrive.requirement(units: imperial),
            "Complete a single drive of 186 mi"
        )
        XCTAssertEqual(
            AchievementCatalogue.longDrive.requirement(units: .metricDefaults),
            "Complete a single drive of 300 km"
        )
        XCTAssertEqual(
            AchievementCatalogue.tenThousandKilometres.requirement(units: imperial),
            "Cover 6,214 mi of recorded driving"
        )
    }

    func testASentenceWithNoDistanceIsLeftAlone() {
        XCTAssertEqual(
            AchievementCatalogue.hundredCharges.requirement(units: .metricDefaults),
            "Record 100 charging sessions"
        )
        XCTAssertEqual(
            AchievementCatalogue.megawattHour.requirement(units: .metricDefaults),
            "Put 1,000 kWh into the pack",
            "Kilowatt-hours do not change with a length preference"
        )
    }

    func testAThresholdInASentenceIsConvertedEvenWhenItIsNotTheTarget() {
        // "Well kept" is scored as a yes-or-no, but its sentence names 50,000 km.
        let imperial = UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")
        XCTAssertEqual(
            AchievementCatalogue.wellKept.requirement(units: imperial),
            "Hold 90% pack health past 31,069 mi"
        )
    }

    func testAFreshInstallHasEarnedNothingAndCrashesOnNothing() {
        let entries = AchievementCatalogue.evaluate(AchievementFacts())
        XCTAssertEqual(entries.count, AchievementCatalogue.all.count)
        XCTAssertTrue(entries.allSatisfy { !$0.isEarned })
        XCTAssertTrue(entries.allSatisfy { $0.percentComplete == 0 })
    }

    // MARK: - The facts

    @MainActor
    private func drive(_ id: Int, distance: Double?, startedDaysAfter: Double) throws -> DriveRecord {
        let dto = DriveSummaryDTO(
            driveId: id,
            startDate: FlexibleDate(start.addingTimeInterval(startedDaysAfter * day)),
            endDate: FlexibleDate(start.addingTimeInterval(startedDaysAfter * day + 1_800)),
            startAddress: "A", endAddress: "B",
            odometerDetails: OdometerDetailsDTO(odometerStart: 0, odometerEnd: distance, odometerDistance: distance),
            durationMin: 30, durationStr: nil, speedMax: 100, speedAvg: 60,
            powerMax: nil, powerMin: nil, outsideTempAvg: nil, insideTempAvg: nil,
            energyConsumedNet: nil, consumptionNet: nil,
            batteryDetails: nil, rangeRated: nil, rangeIdeal: nil
        )
        return DriveRecord(serverID: UUID(), carID: 1, dto: dto)
    }

    @MainActor
    func testDistanceAndTheLongestDriveAreConvertedToKilometres() throws {
        let drives = [
            try drive(1, distance: 100, startedDaysAfter: 0),
            try drive(2, distance: 250, startedDaysAfter: 1)
        ]
        let facts = AchievementFactsBuilder.build(
            drives: drives, charges: [], battery: nil, placesVisited: 0, softwareVersions: 0,
            units: UnitsDTO(unitOfLength: "mi", unitOfPressure: "psi", unitOfTemperature: "F")
        )
        XCTAssertEqual(facts.distanceKilometres, 350 * 1.609_344, accuracy: 0.01)
        XCTAssertEqual(facts.longestDriveKilometres, 250 * 1.609_344, accuracy: 0.01)
        XCTAssertEqual(facts.driveCount, 2)
    }

    @MainActor
    func testAStreakCountsDaysRatherThanDrives() throws {
        // Four errands on Tuesday are one day of driving.
        let drives = [
            try drive(1, distance: 5, startedDaysAfter: 0),
            try drive(2, distance: 5, startedDaysAfter: 0.2),
            try drive(3, distance: 5, startedDaysAfter: 0.4),
            try drive(4, distance: 5, startedDaysAfter: 1),
            try drive(5, distance: 5, startedDaysAfter: 2),
            // A gap, then a shorter run.
            try drive(6, distance: 5, startedDaysAfter: 9),
            try drive(7, distance: 5, startedDaysAfter: 10)
        ]
        let facts = AchievementFactsBuilder.build(
            drives: drives, charges: [], battery: nil, placesVisited: 0, softwareVersions: 0, units: .metricDefaults
        )
        XCTAssertEqual(facts.daysDriven, 5)
        XCTAssertEqual(facts.longestDrivingStreak, 3, "Three consecutive days, then a gap")
    }

    func testTheStreakHelperHandlesTheEdges() {
        let calendar = Calendar.current
        XCTAssertEqual(AchievementFactsBuilder.longestStreak(ofDays: [], calendar: calendar), 0)
        let oneDay: Set<Date> = [calendar.startOfDay(for: start)]
        XCTAssertEqual(AchievementFactsBuilder.longestStreak(ofDays: oneDay, calendar: calendar), 1)
    }

    @MainActor
    func testNightDrivesAreCountedByTheHourTheyBeganIn() throws {
        // Pinned to UTC so the count does not depend on where the test is run:
        // "one in the morning" is a different instant in every timezone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: start)

        var drives: [DriveRecord] = []
        // 01:00 and 02:30 are night; 09:00 and 18:00 are not.
        for (index, hour) in [1.0, 2.5, 9.0, 18.0].enumerated() {
            let at = midnight.addingTimeInterval(hour * 3_600)
            drives.append(try drive(index + 1, distance: 10, startedDaysAfter: at.timeIntervalSince(start) / day))
        }

        let facts = AchievementFactsBuilder.build(
            drives: drives, charges: [], battery: nil, placesVisited: 0, softwareVersions: 0,
            units: .metricDefaults, calendar: calendar
        )
        XCTAssertEqual(facts.nightDrives, 2, "Only the two before four in the morning")
    }
}
