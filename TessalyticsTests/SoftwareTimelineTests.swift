import XCTest
@testable import Tessalytics

/// TeslaMate records the moment a version was *installed*. What an owner wants is
/// the other thing — how long the car then ran it, and which version it was on
/// some day they remember. That is the gap between one install and the next.
final class SoftwareTimelineTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private lazy var start = Date(timeIntervalSince1970: 1_780_000_000)

    private func update(_ id: Int, _ version: String?, daysAfterStart: Double) -> FirmwareUpdateDTO {
        let at = start.addingTimeInterval(daysAfterStart * day)
        return FirmwareUpdateDTO(
            updateId: id,
            startDate: FlexibleDate(at.addingTimeInterval(-1_800)),
            endDate: FlexibleDate(at),
            version: version
        )
    }

    func testEachVersionRunsUntilTheNextOneReplacesIt() {
        let now = start.addingTimeInterval(50 * day)
        let periods = SoftwareTimeline.periods(
            from: [update(1, "2026.8.1", daysAfterStart: 0), update(2, "2026.20.3", daysAfterStart: 30)],
            now: now
        )

        XCTAssertEqual(periods.map(\.version), ["2026.20.3", "2026.8.1"], "Newest first, as the list reads")
        XCTAssertEqual(periods.last?.days(now: now), 30, "Thirty days before it was replaced")
        XCTAssertEqual(periods.first?.days(now: now), 20, "And twenty on the current one so far")
    }

    func testTheNewestVersionIsStillRunning() throws {
        let now = start.addingTimeInterval(10 * day)
        let periods = SoftwareTimeline.periods(from: [update(1, "2026.8.1", daysAfterStart: 0)], now: now)
        let current = try XCTUnwrap(periods.first)
        XCTAssertTrue(current.isCurrent)
        XCTAssertNil(current.supersededAt)
        XCTAssertEqual(current.end(now: now), now, "It runs up to today")
        XCTAssertEqual(current.durationDescription(now: now), "10 days so far")
    }

    func testInstallsArrivingOutOfOrderStillProduceAnOrderedTimeline() {
        // TeslaMateApi promises no ordering.
        let now = start.addingTimeInterval(40 * day)
        let periods = SoftwareTimeline.periods(
            from: [
                update(3, "2026.32.1", daysAfterStart: 30),
                update(1, "2026.8.1", daysAfterStart: 0),
                update(2, "2026.20.3", daysAfterStart: 12)
            ],
            now: now
        )
        XCTAssertEqual(periods.map(\.version), ["2026.32.1", "2026.20.3", "2026.8.1"])
        XCTAssertEqual(periods.map { $0.days(now: now) }, [10, 18, 12])
    }

    func testTwoInstallsOnOneDayAreUnderADayRatherThanADay() {
        // Rounding up would make a version the car ran for twenty minutes look
        // like a day's use.
        let now = start.addingTimeInterval(5 * day)
        let periods = SoftwareTimeline.periods(
            from: [update(1, "2026.8.1", daysAfterStart: 0), update(2, "2026.8.2", daysAfterStart: 0.25)],
            now: now
        )
        XCTAssertEqual(periods.last?.days(now: now), 0)
        XCTAssertEqual(periods.last?.durationDescription(now: now), "Under a day")
    }

    func testAnInstallWithNoDateCannotBePlacedAndIsLeftOut() {
        let undated = FirmwareUpdateDTO(updateId: 9, startDate: nil, endDate: nil, version: "2026.1.1")
        let periods = SoftwareTimeline.periods(from: [undated, update(1, "2026.8.1", daysAfterStart: 0)])
        XCTAssertEqual(periods.map(\.version), ["2026.8.1"])
    }

    func testAVersionTheServerDidNotReportStillOccupiesItsTime() {
        // The gap is real even when the name is missing; dropping it would make
        // the version before it look like it ran for both periods.
        let now = start.addingTimeInterval(20 * day)
        let periods = SoftwareTimeline.periods(
            from: [update(1, "2026.8.1", daysAfterStart: 0), update(2, nil, daysAfterStart: 10)],
            now: now
        )
        XCTAssertEqual(periods.map(\.version), ["Version not reported", "2026.8.1"])
        XCTAssertEqual(periods.last?.days(now: now), 10)
    }

    func testTheSpanCoversEveryPeriod() throws {
        let now = start.addingTimeInterval(40 * day)
        let periods = SoftwareTimeline.periods(
            from: [update(1, "a", daysAfterStart: 0), update(2, "b", daysAfterStart: 30)],
            now: now
        )
        let span = try XCTUnwrap(SoftwareTimeline.span(of: periods, now: now))
        XCTAssertEqual(span.lowerBound, start)
        XCTAssertEqual(span.upperBound, now)
        XCTAssertNil(SoftwareTimeline.span(of: [], now: now), "Nothing to draw")
    }

    func testTheTimelineAnswersWhichVersionRanOnAGivenDay() {
        let now = start.addingTimeInterval(40 * day)
        let periods = SoftwareTimeline.periods(
            from: [update(1, "2026.8.1", daysAfterStart: 0), update(2, "2026.20.3", daysAfterStart: 30)],
            now: now
        )
        XCTAssertEqual(SoftwareTimeline.version(on: start.addingTimeInterval(5 * day), in: periods, now: now), "2026.8.1")
        XCTAssertEqual(SoftwareTimeline.version(on: start.addingTimeInterval(35 * day), in: periods, now: now), "2026.20.3")
        XCTAssertNil(
            SoftwareTimeline.version(on: start.addingTimeInterval(-day), in: periods, now: now),
            "Before the first install there is nothing to say"
        )
    }

    func testNoUpdatesIsAnEmptyTimelineRatherThanACrash() {
        XCTAssertTrue(SoftwareTimeline.periods(from: []).isEmpty)
    }
}
