import XCTest

/// Every figure on the hero card used to open battery health, including the tyre
/// diagram and the week's driving. Each one now leads to the screen it is about.
@MainActor
final class HeroNavigationUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        return app
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(identifier) should be on the hero card")
        element.tap()
    }

    private func back(in app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
    }

    func testTheBatteryRingOpensBatteryHealth() {
        let app = launch()
        tap("vehicle-snapshot-battery", in: app)
        XCTAssertTrue(app.otherElements["battery-health-screen"].waitForExistence(timeout: 10))
    }

    func testTheTyreDiagramOpensTheTyres() {
        // The one that was most obviously wrong: tapping the tyres to read the
        // tyres took you to the battery.
        let app = launch()
        tap("vehicle-snapshot-tyres", in: app)
        XCTAssertTrue(app.otherElements["tyre-pressure-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["tyre-corner-frontLeft"].exists)
    }

    func testTheCarNameOpensItsSettings() {
        let app = launch()
        tap("vehicle-snapshot-identity", in: app)
        XCTAssertTrue(app.otherElements["vehicle-settings-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["vehicle-settings-rating"].waitForExistence(timeout: 5),
            "Vehicle settings carries the rating"
        )
    }

    func testTheVehicleSettingsRatingOpensTheRatingEditor() {
        let app = launch()
        tap("vehicle-snapshot-identity", in: app)
        XCTAssertTrue(app.otherElements["vehicle-settings-screen"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["vehicle-settings-rating"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["specification-capacity-field"].waitForExistence(timeout: 10)
        )
    }

    func testTheOdometerOpensTheDrives() {
        let app = launch()
        tap("vehicle-snapshot-odometer", in: app)
        XCTAssertTrue(app.otherElements["drive-history-screen"].waitForExistence(timeout: 10))
    }

    func testTheWeeksDrivingOpensTheDrives() {
        let app = launch()
        tap("hero-recent-driving", in: app)
        XCTAssertTrue(app.otherElements["drive-history-screen"].waitForExistence(timeout: 10))
    }

    /// The gear the car reports, which the card never showed.
    func testTheHeroShowsTheGearTheCarIsIn() {
        let app = launch()
        let gear = app.descendants(matching: .any)["vehicle-shift-state"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        XCTAssertEqual(gear.value as? String, "Park", "A parked car reports P")
    }

    func testTheSoftwareTimelineIsDrawnAndCounted() {
        let app = launch()
        tap("vehicle-snapshot-identity", in: app)
        XCTAssertTrue(app.otherElements["vehicle-settings-screen"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["vehicle-settings-software"].firstMatch.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["software-version-timeline"].waitForExistence(timeout: 10),
            "A list of versions and dates leaves the arithmetic to the reader"
        )
        // Each row says how long the car ran that version.
        let rows = app.descendants(matching: .any).matching(identifier: "software-version-row")
        XCTAssertGreaterThan(rows.count, 1)
        XCTAssertTrue(
            rows.firstMatch.value as? String != nil,
            "A row's spoken value carries the install date and the duration"
        )
    }

    func testAchievementsAreListedWhetherOrNotGameCenterIsAvailable() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        let achievements = app.descendants(matching: .any)["settings-achievements"].firstMatch
        for _ in 0..<8 where !achievements.exists || !achievements.isHittable { app.swipeUp() }
        XCTAssertTrue(achievements.waitForExistence(timeout: 5))
        achievements.tap()

        XCTAssertTrue(app.otherElements["achievements-screen"].waitForExistence(timeout: 10))
        // The demo car has 248 drives, so the first one is certainly earned.
        let firstDrive = app.descendants(matching: .any)["achievement-\(AchievementIdentifiers.firstDrive)"]
        XCTAssertTrue(firstDrive.firstMatch.waitForExistence(timeout: 5))
    }
}

/// Mirrors the identifiers in `AchievementCatalogue`, which the UI test target
/// cannot import.
enum AchievementIdentifiers {
    static let firstDrive = "com.echocool.Tessalytics.achievement.firstDrive"
}
