import SwiftData
import XCTest
@testable import Tessalytics

@MainActor
final class BatteryLevelHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            ServerProfileRecord.self, VehicleRecord.self, DriveRecord.self,
            ChargeRecord.self, DetailCacheRecord.self, BatteryHealthRecord.self,
            FirmwareUpdateRecord.self, GlobalSettingsRecord.self, SyncMetadataRecord.self,
            TrackRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    private func drive(_ hoursAgo: Double, from start: Int, to end: Int) -> DriveRecord {
        let record = DriveRecord(
            serverID: UUID(),
            carID: 1,
            dto: DriveSummaryDTO(
                driveId: Int(hoursAgo * 10),
                startDate: FlexibleDate(now.addingTimeInterval(-hoursAgo * 3600)),
                endDate: FlexibleDate(now.addingTimeInterval(-hoursAgo * 3600 + 1800)),
                startAddress: nil, endAddress: nil, odometerDetails: nil,
                durationMin: 30, durationStr: nil, speedMax: nil, speedAvg: nil,
                powerMax: nil, powerMin: nil, outsideTempAvg: nil, insideTempAvg: nil,
                energyConsumedNet: nil, consumptionNet: nil,
                batteryDetails: LevelWindowDTO(
                    startBatteryLevel: start, endBatteryLevel: end,
                    startUsableBatteryLevel: nil, endUsableBatteryLevel: nil
                ),
                rangeRated: nil, rangeIdeal: nil
            )
        )
        return record
    }

    func testDrivesAndChargesInterleaveByTime() {
        let points = BatteryLevelHistory.points(
            drives: [drive(48, from: 90, to: 70), drive(10, from: 85, to: 60)],
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            now: now
        )
        XCTAssertEqual(points.map(\.level), [90, 70, 85, 60])
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    func testReadingsOlderThanTheCutoffAreDropped() {
        let points = BatteryLevelHistory.points(
            drives: [drive(24 * 30, from: 99, to: 20), drive(5, from: 60, to: 55)],
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            now: now
        )
        XCTAssertEqual(points.map(\.level), [60, 55])
    }

    func testTheLiveLevelClosesTheSeries() {
        // Without it the chart stops at whatever happened last rather than now.
        let points = BatteryLevelHistory.points(
            drives: [drive(30, from: 80, to: 65)],
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            currentLevel: 77,
            now: now
        )
        XCTAssertEqual(points.last?.level, 77)
        XCTAssertEqual(points.last?.date, now)
    }

    func testReadingsSharingAnInstantCollapse() {
        // A charge ending as a drive begins puts two points on one x position,
        // which draws as a vertical spike.
        let points = BatteryLevelHistory.points(
            drives: [drive(10, from: 80, to: 60), drive(10, from: 60, to: 40)],
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            now: now
        )
        XCTAssertEqual(Set(points.map(\.date)).count, points.count)
    }

    func testImpossibleLevelsAreRejected() {
        let points = BatteryLevelHistory.points(
            drives: [drive(10, from: 140, to: -5)],
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            now: now
        )
        XCTAssertTrue(points.isEmpty)
    }

    func testIdsAreUniqueSoChartMarksAreNotDropped() {
        let points = BatteryLevelHistory.points(
            drives: (1...12).map { drive(Double($0) * 3, from: 90 - $0, to: 80 - $0) },
            charges: [],
            since: now.addingTimeInterval(-7 * 86_400),
            now: now
        )
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
    }

    func testNoHistoryProducesNothing() {
        XCTAssertTrue(
            BatteryLevelHistory.points(drives: [], charges: [], since: now.addingTimeInterval(-86_400), now: now).isEmpty
        )
    }
}
