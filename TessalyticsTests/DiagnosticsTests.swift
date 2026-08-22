import XCTest
@testable import Tessalytics

/// Debug mode keeps raw vehicle data in memory, so the rules about when it does
/// and what leaves the device are the part worth testing.
@MainActor
final class DiagnosticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "diagnostics-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func unlocked() -> Diagnostics {
        let diagnostics = Diagnostics(defaults: defaults)
        diagnostics.unlock()
        return diagnostics
    }

    private static let eventBody = Data(
        """
        {"data":{"state":{"state":"driving","driving":{"shift_state":"D","speed":63.0,"power":34.0},\
        "battery":{"level":71}}},"meta":{"source":"mixed"}}
        """.utf8
    )

    func testNothingIsKeptUntilItIsUnlocked() {
        let diagnostics = Diagnostics(defaults: defaults)
        diagnostics.record(.stream, "Connected")
        diagnostics.recordLiveEvent(body: Self.eventBody)
        XCTAssertTrue(diagnostics.entries.isEmpty, "A log nobody can read is cost with no upside")
        XCTAssertEqual(diagnostics.liveEventsSeen, 0)
    }

    func testUnlockingSurvivesRelaunch() {
        _ = unlocked()
        XCTAssertTrue(Diagnostics(defaults: defaults).isUnlocked)
    }

    func testEventsAreCountedEvenWhenTheirBodiesAreNotKept() {
        // "The stream is up and nothing is arriving" and "readings are arriving
        // and the screen is not showing them" are different problems.
        let diagnostics = unlocked()
        XCTAssertFalse(diagnostics.recordsLiveEvents)
        diagnostics.recordLiveEvent(body: Self.eventBody)
        XCTAssertEqual(diagnostics.liveEventsSeen, 1)
        XCTAssertNotNil(diagnostics.lastLiveEventAt)
        XCTAssertFalse(diagnostics.entries.contains { $0.kind == .liveEvent })
    }

    func testRecordingKeepsTheBodyAndSummarisesIt() {
        let diagnostics = unlocked()
        diagnostics.setRecordsLiveEvents(true)
        diagnostics.recordLiveEvent(body: Self.eventBody)
        let entry = diagnostics.entries.first { $0.kind == .liveEvent }
        XCTAssertEqual(entry?.summary, "driving · D · 63 speed · 34 kW · 71%")
        XCTAssertTrue(entry?.detail?.contains("\"shift_state\"") == true, "The body is kept verbatim")
    }

    func testALogHasACeiling() {
        let diagnostics = unlocked()
        for index in 0..<(Diagnostics.entryCapacity + 25) {
            diagnostics.record(.request, "Entry \(index)")
        }
        XCTAssertEqual(diagnostics.entries.count, Diagnostics.entryCapacity)
        XCTAssertGreaterThan(diagnostics.discardedEntries, 0, "And it says when it has thrown work away")
        XCTAssertEqual(
            diagnostics.entries.first?.summary,
            "Entry \(Diagnostics.entryCapacity + 24)",
            "Newest first, which is the order the screen reads in"
        )
    }

    func testAVeryLongDetailIsTruncatedRatherThanKept() {
        let diagnostics = unlocked()
        diagnostics.record(.request, "Huge", detail: String(repeating: "x", count: 100_000))
        let detail = diagnostics.entries.first?.detail ?? ""
        XCTAssertLessThan(detail.count, Diagnostics.detailCharacterLimit + 200)
        XCTAssertTrue(detail.hasSuffix("characters"))
    }

    func testAnUnparseableBodyIsShownAsItArrived() {
        // A server sending something unexpected is exactly when this is read.
        XCTAssertEqual(Diagnostics.prettyPrinted(Data("not json at all".utf8)), "not json at all")
        XCTAssertNil(Diagnostics.headline(forEventBody: Data("not json at all".utf8)))
    }

    /// The stand-in for a token, deliberately unmistakable.
    ///
    /// This fixture is a public repository's idea of a credential, so it must not
    /// be shaped like one. An earlier version used an `sk-` prefix — the shape
    /// Stripe and OpenAI keys take — and a secret scanner opened an incident
    /// against the commit. The redactor keys on the `Authorization:` and
    /// `token=` labels, not on what follows them, so nothing is lost by making
    /// the value obviously inert.
    private static let notASecret = "EXAMPLE-PLACEHOLDER-NOT-A-REAL-CREDENTIAL"
    /// A VIN's shape, with a serial no car was ever built with.
    private static let sampleVIN = "5YJYGDEE1LF000001"

    func testTheExportIsRedacted() {
        let diagnostics = unlocked()
        diagnostics.record(
            .request,
            "Fetched status",
            detail: "Authorization: Bearer \(Self.notASecret)\n\(Self.sampleVIN)\n37.40621, -122.07234"
        )
        let export = diagnostics.exportText()
        XCTAssertFalse(export.contains(Self.notASecret), "A token must not leave the device")
        XCTAssertFalse(export.contains(Self.sampleVIN), "Nor a VIN")
        XCTAssertFalse(export.contains("37.40621"), "Nor a doorstep")
        XCTAssertTrue(export.contains("Fetched status"), "But the log is still a log")
    }

    /// The footer on the export screen promises the coordinates are gone. It has
    /// to be true of the shape they actually arrive in — named fields inside a
    /// recorded event body, not an inline "lat, lon" pair.
    func testAnExportedEventBodyHasItsCoordinatesRemoved() {
        let diagnostics = unlocked()
        diagnostics.setRecordsLiveEvents(true)
        diagnostics.recordLiveEvent(
            body: Data(
                """
                {"data":{"state":{"state":"driving",                "location":{"latitude":37.40621,"longitude":-122.07234,"geofence":null}}}}
                """.utf8
            )
        )
        let export = diagnostics.exportText()
        XCTAssertFalse(export.contains("37.40621"), "The owner's doorstep must not leave the device")
        XCTAssertFalse(export.contains("-122.07234"))
        XCTAssertTrue(export.contains("latitude"), "The shape of the reading still reads")
        XCTAssertTrue(export.contains("[REDACTED]"))
    }

    func testTheEntryItselfKeepsTheCoordinatesForReadingOnTheDevice() {
        // Redaction is about the export. A log with the positions taken out
        // cannot answer the question a location log exists to answer.
        let diagnostics = unlocked()
        diagnostics.setRecordsLiveEvents(true)
        diagnostics.recordLiveEvent(
            body: Data(#"{"data":{"state":{"location":{"latitude":37.40621}}}}"#.utf8)
        )
        XCTAssertTrue(diagnostics.entries.first?.detail?.contains("37.40621") == true)
    }

    func testTheExportCarriesEnoughContextToBeUseful() {
        let diagnostics = unlocked()
        diagnostics.record(.stream, "Connected")
        let export = diagnostics.exportText(context: ["Server": "teslamate.example"])
        XCTAssertTrue(export.contains("Tessalytics diagnostics"))
        XCTAssertTrue(export.contains("Server: teslamate.example"))
        XCTAssertTrue(export.contains("Live events seen: 0"))
    }

    func testTheExportReadsForwards() {
        let diagnostics = unlocked()
        diagnostics.record(.stream, "First")
        diagnostics.record(.stream, "Second")
        let export = diagnostics.exportText()
        guard let first = export.range(of: "First"), let second = export.range(of: "Second") else {
            return XCTFail("Both entries should be in the export")
        }
        XCTAssertTrue(first.lowerBound < second.lowerBound, "A log is read forwards")
    }

    func testTurningDebugModeOffTakesTheLogWithIt() {
        let diagnostics = unlocked()
        diagnostics.setRecordsLiveEvents(true)
        diagnostics.recordLiveEvent(body: Self.eventBody)
        diagnostics.lock()

        XCTAssertFalse(diagnostics.isUnlocked)
        XCTAssertFalse(diagnostics.recordsLiveEvents, "Recording does not outlive the screen that turned it on")
        XCTAssertTrue(diagnostics.entries.isEmpty)
        XCTAssertFalse(Diagnostics(defaults: defaults).isUnlocked, "And it stays off across a relaunch")
    }
}
