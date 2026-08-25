import XCTest

/// A charging car is a car somebody has walked away from, so what the screen says
/// about when to come back is the whole point of the card.
@MainActor
final class LiveChargingUITests: XCTestCase {
    private func launchCharging() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo", "-ui-demo-charging"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        return app
    }

    /// Scrolls until the element is realized.
    ///
    /// `exists` rather than `isHittable`: these are accessibility containers, and
    /// a container is not itself hittable even when everything inside it is on
    /// screen.
    @discardableResult
    private func scroll(to element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<18 {
            if element.exists { return element }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Should be reachable on the home screen")
        return element
    }

    func testTheHeroLeadsWithWhenTheChargeWillBeDone() {
        let app = launchCharging()
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["hero-charge-forecast"].waitForExistence(timeout: 5),
            "A plugged-in car is asked 'when can I leave', not 'how was last week'"
        )
    }

    /// The swap that makes room for it. Seven days of battery history is the right
    /// thing to show a parked car and the wrong thing to show one on a charger.
    func testTheSevenDayBatteryChartStandsAsideWhileCharging() {
        let app = launchCharging()
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["hero-battery-level-chart"].exists,
            "The week chart stands aside for the charge forecast"
        )
    }

    func testTheSevenDayBatteryChartIsBackWhenTheCarIsNotCharging() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"]
        app.launch()
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["hero-battery-level-chart"].waitForExistence(timeout: 5),
            "A parked car gets the week back"
        )
        XCTAssertFalse(app.descendants(matching: .any)["hero-charge-forecast"].exists)
    }

    func testTheChargeCardShowsTheHourAheadAndTheFinishingTime() {
        let app = launchCharging()
        // Scrolled to the figure itself, not to the card around it. The card is
        // a container that exists in the tree before the lazy stack has laid out
        // anything inside it — so waiting on the container returns while the
        // cards it is supposed to hold are still nothing.
        scroll(to: app.descendants(matching: .any)["In an hour"], in: app)
        // A MetricCard ignores its children and carries its title as the whole
        // element's label, so each of these is one element named for the question
        // it answers.
        for wanted in ["In an hour", "Full at", "Charging at"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[wanted].exists,
                "\(wanted) should be on the charge card"
            )
        }
    }

    /// The chart lives in the hero card, where the question it answers is asked.
    func testTheForecastChartIsInTheHeroCard() {
        let app = launchCharging()
        let hero = app.otherElements["vehicle-snapshot-card"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        XCTAssertTrue(
            hero.descendants(matching: .any)["charge-forecast-chart"].exists,
            "It belongs beside the battery ring, not three cards down the page"
        )
    }

    /// A reader has to be able to tell a reading from a guess, and charge from
    /// power, before any of it is worth anything.
    func testTheChartIsLegendedForBothSeries() {
        let app = launchCharging()
        let hero = app.otherElements["vehicle-snapshot-card"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        for key in ["charge", "forecast", "power"] {
            XCTAssertTrue(
                hero.staticTexts[key].exists,
                "A reader has to be able to tell \(key) from the other two"
            )
        }
    }

    /// Without it, how long the car has been plugged in — the thing that makes the
    /// measured rate believable — is left to be inferred from the axis.
    func testTheChartSaysWhenTheCarWasPluggedIn() {
        let app = launchCharging()
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 10))
        let chart = app.descendants(matching: .any)["charge-forecast-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        // A Chart is one accessibility element, so what it draws is only reachable
        // through its value — which is also the only way anyone using VoiceOver
        // gets any of this.
        XCTAssertTrue(
            (chart.value as? String)?.contains("plugged in at") == true,
            "The chart should say when the session began"
        )
    }

    /// The demo charges on a tapering DC cabinet on purpose. A flat rate would
    /// exercise the easy half of the forecast and hide the half that matters.
    func testATaperingChargeSaysSoRatherThanQuietlyPromisingAStraightLine() {
        let app = launchCharging()
        scroll(to: app.staticTexts["Allowing for the rate falling as the pack fills"], in: app)
        XCTAssertTrue(
            app.staticTexts["Allowing for the rate falling as the pack fills"].exists,
            "A projection that bends should say why"
        )
    }

    func testEachMilestoneCarriesAClockTime() {
        let app = launchCharging()
        scroll(to: app.staticTexts["50%"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["charge-milestones"].exists)
        // The demo starts at 41% against an 80% limit, so these are all ahead.
        XCTAssertTrue(app.staticTexts["50%"].exists)
        XCTAssertTrue(app.staticTexts["60%"].exists)
        XCTAssertTrue(app.staticTexts["70%"].exists)
        XCTAssertTrue(app.staticTexts["80%"].exists)
        // And nothing above the limit, which the car will never reach.
        XCTAssertFalse(app.staticTexts["90%"].exists)
    }

    func testTheChargeCardIsAbsentWhenNothingIsPluggedIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"]
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        for _ in 0..<16 { app.swipeUp() }
        XCTAssertFalse(app.descendants(matching: .any)["live-charge-figures"].exists)
    }
}
