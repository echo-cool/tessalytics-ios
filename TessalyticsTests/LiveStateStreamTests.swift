import XCTest
@testable import Tessalytics

/// The stream is the only path live readings take to the screen, and every one of
/// these rules is a way for a drive's worth of them to disappear quietly.
final class EventFramingTests: XCTestCase {
    private func bodies(_ lines: [String]) -> [String] {
        var framing = EventFraming()
        return lines.compactMap { framing.consume(line: $0) }.map { String(decoding: $0, as: UTF8.self) }
    }

    /// The framing as the stream actually drives it: one byte at a time.
    ///
    /// Tested at this level deliberately. The line-based tests below all passed
    /// while the feature was completely broken, because the stream fed itself from
    /// `AsyncLineSequence`, which does not report the blank line that ends an
    /// event. Nothing that took lines as given could have caught it.
    private func bodies(bytes text: String) -> [String] {
        var framing = EventFraming()
        return Array(text.utf8).compactMap { framing.consume(byte: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
    }

    func testEventsAreFramedFromRawBytes() {
        XCTAssertEqual(
            bodies(bytes: "event: state\ndata: {\"a\":1}\n\nevent: state\ndata: {\"a\":2}\n\n"),
            ["{\"a\":1}", "{\"a\":2}"]
        )
    }

    func testTheBlankLineIsWhatEndsAnEvent() {
        // The bug: without this byte nothing is emitted, and with only `\n` after
        // the data line the event is still open.
        XCTAssertTrue(bodies(bytes: "data: {\"a\":1}\n").isEmpty)
        XCTAssertEqual(bodies(bytes: "data: {\"a\":1}\n\n"), ["{\"a\":1}"])
    }

    func testCarriageReturnsAreNotPartOfTheValue() {
        // A CRLF stream is legal, and a trailing CR inside the JSON breaks the
        // decode rather than the framing, which is worse: it looks like bad data.
        XCTAssertEqual(bodies(bytes: "data: {\"a\":1}\r\n\r\n"), ["{\"a\":1}"])
    }

    func testKeepAlivesBetweenEventsEmitNothing() {
        XCTAssertEqual(
            bodies(bytes: ": keep-alive\n\ndata: x\n\n: keep-alive\n\n"),
            ["x"]
        )
    }

    func testAnEventArrivingInPiecesIsStillOneEvent() {
        var framing = EventFraming()
        var emitted: [String] = []
        for chunk in ["event: sta", "te\ndata: {\"a\":", "1}\n", "\n"] {
            for byte in Array(chunk.utf8) {
                if let body = framing.consume(byte: byte) {
                    emitted.append(String(decoding: body, as: UTF8.self))
                }
            }
        }
        XCTAssertEqual(emitted, ["{\"a\":1}"])
    }

    func testAnEventIsCompletedByItsBlankLine() {
        XCTAssertEqual(bodies(["event: state", "data: {\"a\":1}", ""]), ["{\"a\":1}"])
    }

    func testNothingIsEmittedBeforeTheBlankLine() {
        // Emitting on the data line would publish a half-received event whenever a
        // payload arrived split across two reads.
        XCTAssertTrue(bodies(["event: state", "data: {\"a\":1}"]).isEmpty)
    }

    func testKeepAliveCommentsDoNotEmitAnEvent() {
        // The server sends these every fifteen seconds so the connection and the
        // proxies in front of it stay awake. They are not readings.
        XCTAssertTrue(bodies([": keep-alive", ""]).isEmpty)
    }

    func testConsecutiveEventsDoNotBleedIntoEachOther() {
        let lines = ["data: {\"a\":1}", "", "data: {\"a\":2}", "", "data: {\"a\":3}", ""]
        XCTAssertEqual(bodies(lines), ["{\"a\":1}", "{\"a\":2}", "{\"a\":3}"])
    }

    func testMultipleDataLinesAreJoinedWithNewlines() {
        XCTAssertEqual(bodies(["data: {\"a\":", "data: 1}", ""]), ["{\"a\":\n1}"])
    }

    func testTheSpaceAfterTheColonIsOptional() {
        XCTAssertEqual(bodies(["data:{\"a\":1}", ""]), ["{\"a\":1}"])
    }

    func testFieldsOtherThanDataAreIgnored() {
        XCTAssertEqual(bodies(["id: 7", "retry: 5000", "event: state", "data: x", ""]), ["x"])
    }
}

/// The body of a `state` event is the body of `/state`. These decode the shape the
/// backend actually sends, because the stream once decoded a different one: it
/// connected, showed itself live, and silently discarded every reading, leaving a
/// poll every thirty seconds as the only thing that moved the numbers.
final class LiveStateDecodingTests: XCTestCase {
    /// A `state` event, as the deployed backend sends it while driving.
    private let body = """
    {"data":{"state":{"vehicle_id":1,"state":"driving","state_since":"2026-08-21T02:32:18Z",
    "name":"wyy","healthy":true,
    "location":{"latitude":37.36705,"longitude":-121.983088,"geofence":null,"heading":120,"elevation":31},
    "battery":{"level":71,"usable_level":71,"buffer":0,"range":234.8,"range_rated":234.8},
    "climate":{"inside_temperature":21.5,"outside_temperature":19.0,"is_climate_on":false},
    "driving":{"shift_state":"D","speed":63.0,"power":34.0,"odometer":33938.43,"is_user_present":true},
    "charging":{"plugged_in":false,"state":"Disconnected"},
    "security":{"locked":true,"sentry_mode":false},
    "tyres":{"front_left":{"pressure":2.825,"warning":false}},
    "software":{"version":"2026.21.6"}}},
    "meta":{"source":"mixed","units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
    """

    func testAStateEventDecodesIntoTheStatusTheViewsRead() throws {
        let decoded = try XCTUnwrap(
            LiveStateStream.decode(body: Data(body.utf8), carID: 1),
            "The stream must decode the envelope the backend sends"
        )

        XCTAssertEqual(decoded.status.state, "driving")
        XCTAssertTrue(decoded.status.isDriving)
        // The readings the live views are for.
        XCTAssertEqual(decoded.status.drivingDetails?.speed, 63)
        XCTAssertEqual(decoded.status.drivingDetails?.power, 34)
        XCTAssertEqual(decoded.status.drivingDetails?.heading, 120)
        XCTAssertEqual(decoded.status.carGeodata?.location?.latitude, 37.36705)
        XCTAssertEqual(decoded.status.batteryDetails?.batteryLevel, 71)
        XCTAssertEqual(decoded.status.odometer, 33938.43)
        XCTAssertNotNil(decoded.status.stateSince?.value, "The live route is fetched from the drive's start")
        XCTAssertEqual(decoded.units?.unitOfLength, "mi")
        XCTAssertEqual(decoded.car.carId, 1)
    }

    func testAnUnrecognisableBodyIsDroppedRatherThanCrashing() {
        XCTAssertNil(LiveStateStream.decode(body: Data(#"{"data":{}}"#.utf8), carID: 1))
        XCTAssertNil(LiveStateStream.decode(body: Data("not json".utf8), carID: 1))
    }
}

final class RetryScheduleTests: XCTestCase {
    private let delays: [UInt64] = [1, 2, 5, 10, 20]

    func testRepeatedFailuresBackOffAndThenHoldAtTheLongestDelay() {
        var schedule = RetrySchedule(delays: delays, resetAfter: .seconds(20))
        let observed = (0..<7).map { _ in schedule.next(afterConnectionLasting: .zero) }
        XCTAssertEqual(observed, [1, 2, 5, 10, 20, 20, 20])
    }

    func testAConnectionThatStayedUpDoesNotAgeTheBackoff() {
        // Six tunnels on one drive must not add up to a twenty-second wait for the
        // next reading: each connection worked, so each drop starts again at one.
        var schedule = RetrySchedule(delays: delays, resetAfter: .seconds(20))
        for _ in 0..<6 {
            XCTAssertEqual(schedule.next(afterConnectionLasting: .seconds(600)), 1)
        }
    }

    func testAConnectionThatFailedImmediatelyKeepsBackingOff() {
        var schedule = RetrySchedule(delays: delays, resetAfter: .seconds(20))
        XCTAssertEqual(schedule.next(afterConnectionLasting: .seconds(19)), 1)
        XCTAssertEqual(schedule.next(afterConnectionLasting: .seconds(1)), 2)
        XCTAssertEqual(schedule.next(afterConnectionLasting: .seconds(30)), 1, "The long connection resets it")
    }
}
