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

    /// A moving drive, advancing at the rate a car publishes.
    private func launchMovingDrive(gappy: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo", "-ui-demo-driving", "-ui-demo-driving-live"]
        if gappy { app.launchArguments.append("-ui-demo-gappy-readings") }
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        return app
    }

    /// The reported bug: the map flashed red to black and back, several times a
    /// minute, for the whole of a drive.
    ///
    /// The cause was one reading arriving without a position. The hero card had
    /// two layouts — one with a map and one without — so a gap swapped the whole
    /// card, tore `MKMapView` down and put an empty map surface up in its place
    /// when the next reading brought the position back.
    ///
    /// `-ui-demo-gappy-readings` reproduces that fault on demand: a third of the
    /// readings arrive with no position at all. The map must not blink.
    func testTheMapSurvivesReadingsThatArriveWithoutAPosition() {
        let app = launchMovingDrive(gappy: true)
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        // Long enough to cover many gaps: the fault fires roughly every second.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            XCTAssertTrue(map.exists, "The map left the screen — that is the flash")
        }
    }

    func testTheMapStaysPutWhileTheCarIsMoving() {
        let app = launchMovingDrive()
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            XCTAssertTrue(map.exists, "A moving car must not rebuild the card it is drawn on")
        }
    }

    /// The headline used to say "Driving" and nothing else, which at a red light
    /// is the least informative moment to say the least informative thing.
    func testStandingAtALightSaysSoAndSaysWhere() {
        let app = launchMovingDrive()
        XCTAssertTrue(
            app.descendants(matching: .any)["vehicle-headline"].firstMatch.waitForExistence(timeout: 10),
            "There is a headline to read"
        )

        // The generated drive brakes for a light about twenty-six seconds in and
        // stands there for eighteen. Matched on the text rather than on one
        // element's label: the headline lives inside a button, and a button
        // reports its children combined.
        let stopped = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Stopped"))
            .firstMatch
        XCTAssertTrue(
            stopped.waitForExistence(timeout: 90),
            "The generated drive stops at a light and the hero should say so, not 'Driving · 0 mph'"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["vehicle-place"].firstMatch.exists,
            "And a stopped car has room to say where it is standing"
        )
    }

    /// Only shown when the server reports it — which the generated drive does,
    /// in both states, so a badge stuck on would fail this too.
    func testTheSelfDrivingBadgeFollowsWhatTheServerReports() {
        let app = launchMovingDrive()
        let badge = app.descendants(matching: .any)["self-driving-badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10))

        let deadline = Date().addingTimeInterval(120)
        var seen = Set<String>()
        while Date() < deadline, seen.count < 2 {
            if badge.exists { seen.insert(badge.label) }
        }
        XCTAssertEqual(
            seen,
            ["Full Self-Driving engaged", "Driving manually"],
            "The badge should follow the car, not sit on one value"
        )
    }

    func testTheStaticDrivingDemoShowsWhatIsSteering() {
        let app = launchDriving()
        let badge = app.descendants(matching: .any)["self-driving-badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertEqual(badge.label, "Full Self-Driving engaged")
    }

    func testTheFullScreenMapNamesTheDirectionOfTravel() {
        let app = launchDriving()
        let map = heroMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.tap()
        XCTAssertTrue(app.descendants(matching: .any)["live-map-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["live-metric-heading"].exists)
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
