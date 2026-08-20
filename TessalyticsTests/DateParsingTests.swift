import XCTest
@testable import Tessalytics

/// Tests for timestamp parsing.
///
/// A server that omits the timezone offset used to make every drive look like it
/// was still in progress, because a nil end date is how the app expresses that.
final class DateParsingTests: XCTestCase {
    func testOffsetLessTimestampIsTreatedAsUTC() throws {
        // What a Postgres `timestamp without time zone` looks like via isoformat().
        let parsed = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.326000"))
        let expected = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.326000+00:00"))
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testOffsetLessTimestampWithoutFractionalSeconds() throws {
        let parsed = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16"))
        XCTAssertEqual(
            parsed.timeIntervalSince1970,
            try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16Z")).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testAnExplicitOffsetIsHonouredNotOverridden() throws {
        // -07:00 is seven hours behind the same wall clock in UTC.
        let pacific = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-19T14:37:00-07:00"))
        let utc = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-19T14:37:00Z"))
        XCTAssertEqual(pacific.timeIntervalSince(utc), 7 * 3600, accuracy: 1)
    }

    func testZuluAndPlusZeroAgree() throws {
        let zulu = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16Z"))
        let plus = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16+00:00"))
        XCTAssertEqual(zulu, plus)
    }

    func testTeslaMatesSentinelDatesAreStillRejected() {
        // TeslaMate emits this for "no scheduled charge"; it must not become a
        // real date in the year zero.
        XCTAssertNil(FlexibleDateParser.date(from: "0000-12-31T16:07:02-07:52"))
        XCTAssertNil(FlexibleDateParser.date(from: ""))
        XCTAssertNil(FlexibleDateParser.date(from: "not a date"))
    }

    func testDrivesDecodedFromAnOffsetLessServerAreNotAllInProgress() throws {
        // The end-to-end symptom, pinned.
        let json = Data("""
        {"data":{"drives":[
          {"id":841,"start_date":"2026-08-20T06:05:16.326000","end_date":"2026-08-20T06:08:47.464000","distance":6.7},
          {"id":840,"start_date":"2026-08-20T06:04:22.613000","end_date":null,"distance":0.1}
        ]},"meta":{}}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(BackendEnvelope<BackendDriveListDTO>.self, from: json)
        let summaries = payload.data.drives.map(\.summaryDTO)

        XCTAssertNotNil(summaries[0].endDate?.value, "A finished drive must not read as in progress")
        XCTAssertNotNil(summaries[0].startDate?.value, "A nil start date collapses sorting")
        XCTAssertNil(summaries[1].endDate?.value, "A genuinely open drive stays open")
    }

    func testDrivesSortNewestFirstOnceDatesParse() throws {
        let json = Data("""
        {"data":{"drives":[
          {"id":839,"start_date":"2026-08-20T05:59:21.555000","end_date":"2026-08-20T06:02:18.370000"},
          {"id":841,"start_date":"2026-08-20T06:05:16.326000","end_date":"2026-08-20T06:08:47.464000"},
          {"id":840,"start_date":"2026-08-20T06:04:22.613000","end_date":"2026-08-20T06:04:44.444000"}
        ]},"meta":{}}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let drives = try decoder.decode(BackendEnvelope<BackendDriveListDTO>.self, from: json)
            .data.drives.map(\.summaryDTO)
        let sorted = drives.sorted { ($0.startDate?.value ?? .distantPast) > ($1.startDate?.value ?? .distantPast) }
        XCTAssertEqual(sorted.map(\.driveId), [841, 840, 839])
    }
}

// MARK: - Sub-second precision

extension DateParsingTests {
    /// Regression: microsecond timestamps collapsed onto whole seconds.
    ///
    /// Postgres renders six fractional digits. `.withFractionalSeconds` matches
    /// exactly three, so the six-digit form fell through to the whole-second
    /// parser and every sample inside one second became the same instant — which
    /// made a `Chart` keyed on date drop hundreds of marks.
    func testMicrosecondTimestampsKeepTheirSubSecondPrecision() throws {
        let a = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.326000+00:00"))
        let b = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.892000+00:00"))
        XCTAssertNotEqual(a, b, "Two samples in the same second must stay distinct")
        XCTAssertEqual(b.timeIntervalSince(a), 0.566, accuracy: 0.002)
    }

    func testDenseSamplesStayDistinctAcrossASecond() throws {
        // The shape of the real payload: several samples per second.
        let stamps = (0..<10).map { "2026-08-20T06:05:16.\(String(format: "%06d", $0 * 100_000))+00:00" }
        let parsed = stamps.compactMap { FlexibleDateParser.date(from: $0) }
        XCTAssertEqual(parsed.count, 10)
        XCTAssertEqual(Set(parsed).count, 10, "Every sample must land on its own instant")
        XCTAssertEqual(parsed, parsed.sorted(), "Order must survive normalisation")
    }

    func testFractionNormalisationHandlesEveryDigitCount() {
        let normalise = FlexibleDateParser.millisecondNormalised
        XCTAssertEqual(normalise("2026-08-20T06:05:16.326000+00:00"), "2026-08-20T06:05:16.326+00:00")
        XCTAssertEqual(normalise("2026-08-20T06:05:16.3+00:00"), "2026-08-20T06:05:16.300+00:00")
        XCTAssertEqual(normalise("2026-08-20T06:05:16.32+00:00"), "2026-08-20T06:05:16.320+00:00")
        XCTAssertEqual(normalise("2026-08-20T06:05:16.326+00:00"), "2026-08-20T06:05:16.326+00:00")
        // Nothing to normalise, and the date's own hyphens are not a fraction.
        XCTAssertEqual(normalise("2026-08-20T06:05:16+00:00"), "2026-08-20T06:05:16+00:00")
        XCTAssertEqual(normalise("2026-08-20"), "2026-08-20")
    }

    func testMicrosecondsWithoutAnOffsetAreStillUTCAndPrecise() throws {
        // The offset-less form the backend used to emit.
        let a = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.326000"))
        let b = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.826000"))
        XCTAssertEqual(b.timeIntervalSince(a), 0.5, accuracy: 0.002)
    }

    /// A chart mark keyed on a shared timestamp is dropped, so identity is the
    /// sample's own index.
    func testChartSamplesAreUniqueEvenWhenTimestampsRepeat() {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<5).map { ChartSample(id: $0, date: instant, value: Double($0)) }
        XCTAssertEqual(Set(samples.map(\.id)).count, 5)
    }
}

// MARK: - Cache round trip

extension DateParsingTests {
    /// Regression: the local detail cache truncated timestamps on the way out.
    ///
    /// `FlexibleDate` is encoded into `DetailCacheRecord`, so a lossy encoder
    /// silently degraded every cached drive even though parsing was exact.
    func testEncodingKeepsSubSecondPrecisionThroughARoundTrip() throws {
        let stamps = [
            "2026-08-20T06:05:16.326000+00:00",
            "2026-08-20T06:05:16.892000+00:00",
            "2026-08-20T06:05:17.104000+00:00"
        ]
        let originals = stamps.map { FlexibleDate(FlexibleDateParser.date(from: $0)) }
        XCTAssertEqual(Set(originals.map(\.value)).count, 3)

        let encoded = try JSONEncoder().encode(originals)
        let decoded = try JSONDecoder().decode([FlexibleDate].self, from: encoded)

        XCTAssertEqual(Set(decoded.map(\.value)).count, 3, "A round trip must not merge distinct instants")
        for (original, restored) in zip(originals, decoded) {
            let a = try XCTUnwrap(original.value)
            let b = try XCTUnwrap(restored.value)
            XCTAssertEqual(a.timeIntervalSince1970, b.timeIntervalSince1970, accuracy: 0.002)
        }
    }

    func testEncodedStringCarriesMilliseconds() throws {
        let date = try XCTUnwrap(FlexibleDateParser.date(from: "2026-08-20T06:05:16.326000+00:00"))
        XCTAssertTrue(FlexibleDateParser.string(from: date).contains(".326"))
    }
}
