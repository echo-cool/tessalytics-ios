import XCTest
@testable import Tessalytics

/// A new TeslaMate install cannot fill the derived charts, and the app has to say
/// so rather than showing a screen of blanks that reads as broken.
final class HistoryCoverageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func dates(_ daysAgo: [Double]) -> [Date] {
        daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
    }

    func testNothingRecordedSaysSo() {
        XCTAssertEqual(HistoryCoverage.summary(of: [], now: now), "No completed drives or charges recorded yet.")
    }

    func testAFirstDaySaysItIsAllFromToday() {
        // Not "over 0 days", which reads as a bug.
        let summary = HistoryCoverage.summary(of: dates([0.1, 0.3, 0.6]), now: now)
        XCTAssertEqual(summary, "3 drives and charges, all from today.")
    }

    func testASingleEventIsSingular() {
        XCTAssertEqual(HistoryCoverage.summary(of: dates([2]), now: now), "1 drive and charge over 2 days.")
    }

    func testAFortnightOfRegularUseNeedsNoNotice() {
        let summary = HistoryCoverage.summary(of: dates([15, 14, 12, 9, 7, 5, 3, 2, 1]), now: now)
        XCTAssertNil(summary, "Enough span and enough events: the charts stand on their own")
    }

    func testALongButSparseHistoryStillCounts() {
        // Three months of data and four events cannot support a degradation trend,
        // so the span alone must not clear the notice. The day count itself is not
        // asserted exactly: a span that crosses a daylight-saving change is a day
        // shorter or longer, and that is the calendar being right.
        let summary = HistoryCoverage.summary(of: dates([90, 60, 30, 2]), now: now)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.hasPrefix("4 drives and charges over ") == true, "\(summary ?? "nil")")
        XCTAssertTrue(summary?.hasSuffix(" days.") == true, "\(summary ?? "nil")")
    }

    func testAShortButBusyHistoryStillCounts() {
        // Plenty of events, but a degradation trend over two days is noise.
        let dense = Array(repeating: 1.0, count: 20).enumerated().map { Double($0.offset) * 0.1 }
        XCTAssertNotNil(HistoryCoverage.summary(of: dates(dense), now: now))
    }
}

final class ExplorableTrendPointTests: XCTestCase {
    /// The plotted points sit at whole indices; a trend that shares their x
    /// quantity but not their x values has to land between them.
    func testATrendIsPlacedBetweenTheReadingsItFallsBetween() {
        let odometers: [Double] = [1_000, 2_000, 3_000, 4_000]
        let placed = ExplorableTrendPoint.positioned(
            [(x: 1_000, y: 10), (x: 2_500, y: 20), (x: 4_000, y: 30)],
            onto: odometers
        )
        XCTAssertEqual(placed.map(\.position), [0, 1.5, 3])
        XCTAssertEqual(placed.map(\.value), [10, 20, 30])
    }

    func testPointsOutsideThePlottedRangeAreClampedNotDropped() {
        let placed = ExplorableTrendPoint.positioned(
            [(x: 0, y: 1), (x: 9_999, y: 2)],
            onto: [1_000, 2_000, 3_000]
        )
        XCTAssertEqual(placed.map(\.position), [0, 2])
    }

    func testRepeatedReadingsAtOneValueDoNotDivideByZero() {
        let placed = ExplorableTrendPoint.positioned(
            [(x: 2_000, y: 5)],
            onto: [1_000, 2_000, 2_000, 3_000]
        )
        XCTAssertEqual(placed.count, 1)
        XCTAssertTrue(placed[0].position.isFinite)
    }

    func testASeriesTooShortToHaveAnIndexSpaceYieldsNothing() {
        XCTAssertTrue(ExplorableTrendPoint.positioned([(x: 1, y: 1)], onto: [1_000]).isEmpty)
    }
}
