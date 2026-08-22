import XCTest

/// Captures the App Store screenshot set from generated demo data.
///
/// A UI test rather than a manual pass: the set has to be re-taken for every
/// device class Apple requires and every time the screens change, and the last
/// set went five versions stale because taking it was a chore. It also runs on any
/// simulator without an interactive session, which is what makes the iPad set
/// possible at all.
///
/// Demo mode is deliberate. These images are published, and the real vehicle's
/// addresses, geofences and VIN must never be in them.
///
/// Skipped unless `TESSALYTICS_SCREENSHOT_DIR` is set, so a normal test run is
/// unaffected:
///
///     TEST_RUNNER_TESSALYTICS_SCREENSHOT_DIR=/path/out xcodebuild test \
///       -only-testing:TessalyticsUITests/ScreenshotCaptureTests ...
@MainActor
final class ScreenshotCaptureTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["TESSALYTICS_SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TESSALYTICS_SCREENSHOT_DIR to capture the screenshot set.")
        }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func testCaptureAppStoreSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"]
        app.launch()

        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 20))
        // The hero animates its ring in; capture after it settles.
        sleep(3)
        try capture(named: "01-status")

        try openFromHome(app, card: "Places", as: "02-places")
        try openFromHome(app, card: "Battery", as: "03-battery")

        // Scoped to the tab bar: "Analysis" also labels a quick-link tile on the
        // dashboard, and an unscoped query matches both.
        tab(app, "Analysis").tap()
        XCTAssertTrue(app.staticTexts["Reporting period"].waitForExistence(timeout: 10))
        sleep(2)
        try capture(named: "04-analysis")

        tab(app, "Activity").tap()
        sleep(2)
        try capture(named: "05-activity")
    }

    /// The screens the App Store set does not cover, for the README.
    ///
    /// Separate from the store set because these are documentation rather than
    /// marketing: the store wants five polished screens, and a README wants to
    /// show what the app actually does.
    func testCaptureDocumentationSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 20))
        sleep(3)

        // The car's own settings, and the pack its VIN identifies.
        app.descendants(matching: .any)["vehicle-snapshot-identity"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["vehicle-settings-screen"].waitForExistence(timeout: 10))
        sleep(1)
        try capture(named: "06-vehicle-settings")

        app.descendants(matching: .any)["vehicle-settings-rating"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["specification-capacity-field"].waitForExistence(timeout: 10))
        sleep(1)
        try capture(named: "07-vehicle-rating-vin")
        back(app)

        // Every version the car has run, and how long it ran it.
        app.descendants(matching: .any)["vehicle-settings-software"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["software-version-timeline"].waitForExistence(timeout: 10))
        sleep(2)
        try capture(named: "08-software-timeline")
        back(app)
        back(app)

        // The tyres, with the car's own warnings.
        tab(app, "Status").tap()
        app.descendants(matching: .any)["vehicle-snapshot-tyres"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["tyre-pressure-screen"].waitForExistence(timeout: 10))
        sleep(1)
        try capture(named: "09-tyres")
        back(app)

        // Achievements.
        tab(app, "Settings").tap()
        let achievements = app.descendants(matching: .any)["settings-achievements"].firstMatch
        for _ in 0..<8 where !achievements.exists || !achievements.isHittable { app.swipeUp() }
        achievements.tap()
        XCTAssertTrue(app.otherElements["achievements-screen"].waitForExistence(timeout: 10))
        sleep(1)
        try capture(named: "10-achievements")
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
    }

    /// Opens a navigable card from the dashboard, captures it, and comes back.
    private func openFromHome(_ app: XCUIApplication, card: String, as name: String) throws {
        tab(app, "Status").tap()
        let target = app.staticTexts[card]
        for _ in 0..<12 where !target.isHittable {
            app.swipeUp()
        }
        guard target.isHittable else {
            XCTFail("Could not reach the \(card) card")
            return
        }
        target.tap()
        sleep(3)
        try capture(named: name)
        // Back to the top, so the next search starts from a known position.
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
    }

    /// The tab bar's own button, which on iPad is a sidebar item instead.
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[name]
        if inTabBar.exists { return inTabBar }
        return app.buttons.matching(identifier: name).firstMatch
    }

    /// Writes the full-screen image at the device's native resolution.
    private func capture(named name: String) throws {
        let image = XCUIScreen.main.screenshot().image
        guard let data = image.pngData() else {
            XCTFail("Could not encode \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)

        // Also attach it, so a failed run still shows what it saw.
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
