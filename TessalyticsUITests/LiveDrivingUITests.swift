import XCTest

/// The live driving screens, driven through the generated demo drive.
///
/// The map on the hero card used to be decoration: it sat inside the navigation
/// link that wrapped the whole card, so a tap on it opened battery health. These
/// tests hold the parts of that which a refactor can quietly undo — that the map
/// is a control of its own, that it leads to the full-screen map, and that the
/// grid of live figures fills all six of its places.
@MainActor
final class LiveDrivingUITests: XCTestCase {
    private func launchDriving() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo", "-ui-demo-driving"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        return app
    }

    private func heroMap(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["hero-live-map"].firstMatch
    }

    func testTheMapOnTheHeroCardIsAControlOfItsOwn() {
        let app = launchDriving()
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10), "A driving car draws a map, and the map is tappable")
        XCTAssertTrue(map.isHittable)
    }

    func testTappingTheMapOpensTheFullScreenMap() {
        let app = launchDriving()
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["live-map-screen"].waitForExistence(timeout: 10),
            "The map leads to the map, not to battery health"
        )
        XCTAssertTrue(app.descendants(matching: .any)["live-map-readout"].exists, "With the live figures over it")
        XCTAssertTrue(app.buttons["live-map-follow"].exists)

        app.buttons["live-map-close"].tap()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
    }

    func testTheFullScreenMapShowsTheLiveFiguresOverIt() {
        let app = launchDriving()
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.tap()
        XCTAssertTrue(app.descendants(matching: .any)["live-map-screen"].waitForExistence(timeout: 10))

        for metric in ["speed", "power", "battery", "range", "distance", "energy", "consumption", "outside", "elevation"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["live-metric-\(metric)"].exists,
                "The map is missing its \(metric) reading"
            )
        }
    }

    func testTheHeroGridFillsAllSixOfItsPlaces() {
        // Three across and two down. Four figures left two holes in it.
        let app = launchDriving()
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 10))
        for metric in ["speed", "power", "distance", "energy", "outside", "elevation"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["live-metric-\(metric)"].waitForExistence(timeout: 5),
                "The hero card is missing its \(metric) reading"
            )
        }
    }

    func testTheHomeScreenDrawsTheLiveChartsThatAreTurnedOnByDefault() {
        let app = launchDriving()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        let speed = app.descendants(matching: .any)["live-chart-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["live-chart-power"].waitForExistence(timeout: 5))
    }
}
