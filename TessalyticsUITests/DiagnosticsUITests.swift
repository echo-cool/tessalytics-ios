import XCTest

/// Debug mode: hidden behind five taps on the version number, and hidden again
/// when it is turned off. Both halves matter — a hatch that cannot be closed is
/// just a screen.
@MainActor
final class DiagnosticsUITests: XCTestCase {
    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        // Reset, so a previous run's unlocked state is not what this one observes.
        app.launchArguments = ["-ui-demo", "-diagnosticsUnlocked", "NO", "-diagnosticsRecordsLiveEvents", "NO"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        return app
    }

    private func version(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings-version"].firstMatch
    }

    private func scrollToVersion(in app: XCUIApplication) -> XCUIElement {
        let row = version(in: app)
        for _ in 0..<8 where !row.exists || !row.isHittable {
            app.swipeUp()
        }
        return row
    }

    func testTheDebugScreenIsNotThereUntilItIsAskedFor() {
        let app = launchSettings()
        _ = scrollToVersion(in: app)
        XCTAssertFalse(
            app.descendants(matching: .any)["settings-diagnostics"].firstMatch.exists,
            "Nothing on the debug screen helps anyone understand their car"
        )
    }

    func testFiveTapsOnTheVersionOpenTheDoor() {
        let app = launchSettings()
        let row = scrollToVersion(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<5 { row.tap() }

        // The confirmation offers to open it straight away.
        let open = app.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Five taps should say something happened")
        open.tap()

        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-record-toggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-event-count"].exists)
    }

    func testTheDebugScreenShowsTheRawStatusAndCanExportIt() {
        let app = launchSettings()
        let row = scrollToVersion(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<5 { row.tap() }
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        app.buttons["Open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-screen"].waitForExistence(timeout: 10))

        let raw = app.descendants(matching: .any)["diagnostics-raw-status"].firstMatch
        for _ in 0..<8 where !raw.exists || !raw.isHittable { app.swipeUp() }
        XCTAssertTrue(raw.waitForExistence(timeout: 5), "The reading the app is drawing from, exactly as it holds it")
        raw.tap()
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-entry-screen"].waitForExistence(timeout: 5))
    }

    func testTurningDebugModeOffHidesItAgain() {
        let app = launchSettings()
        let row = scrollToVersion(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<5 { row.tap() }
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        app.buttons["Open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-screen"].waitForExistence(timeout: 10))

        let lock = app.descendants(matching: .any)["diagnostics-lock"].firstMatch
        for _ in 0..<10 where !lock.exists || !lock.isHittable { app.swipeUp() }
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.tap()

        // Turning it off closes the screen and takes the entry point with it.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings-version"].firstMatch.waitForExistence(timeout: 10),
            "Back in Settings"
        )
        XCTAssertFalse(app.descendants(matching: .any)["diagnostics-screen"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["settings-diagnostics"].firstMatch.exists,
            "A hatch that cannot be closed is just a screen"
        )
    }
}
