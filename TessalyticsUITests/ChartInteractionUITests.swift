import XCTest

/// The charts as an owner meets them: a card that says what it is, and a screen
/// behind it that answers "what exactly was that value".
@MainActor
final class ChartInteractionUITests: XCTestCase {
    func testTheHomeScreenIsTitledWithTheAppNotTheCar() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        // The car is named twice already, on the hero card and in the picker, and a
        // long name truncates to nothing in a navigation bar.
        XCTAssertTrue(app.navigationBars["Tessalytics"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Aurora"].exists)
    }

    func testTheCapacityDetailDrawsTheSameChartAsTheCard() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))

        let card = app.buttons["section-card-battery-capacity"]
        scrollTo(card, in: app)
        card.tap()

        // Same three series as the card, named the same way. A detail screen that
        // redraws the same numbers in a different form makes a reader work out
        // whether they are even looking at the same thing.
        XCTAssertTrue(app.staticTexts["Per charge"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Semi-monthly median"].exists)
        XCTAssertTrue(app.staticTexts["When new"].exists)
        // And it is the points form by default, as the card draws it.
        XCTAssertTrue(app.buttons["Points"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chart-explorer-plot"].exists)
    }

    func testACapacityValueCanBeReadOffTheChart() {
        let app = launch("-ui-demo")
        let card = app.buttons["section-card-battery-capacity"]
        scrollTo(card, in: app)
        card.tap()

        let plot = app.descendants(matching: .any)["chart-explorer-plot"]
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        plot.press(forDuration: 0.6)

        // A held finger names the reading and offers to let it go again.
        XCTAssertTrue(app.buttons["chart-clear-reading"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["chart-explorer-table"].exists, "The raw values are listed")
    }

    func testADriveChartOpensItsOwnReadableScreen() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        app.buttons["Activity"].tap()
        XCTAssertTrue(app.otherElements["activity-screen"].waitForExistence(timeout: 5))

        let drive = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "drive-card-")
        ).firstMatch
        XCTAssertTrue(drive.waitForExistence(timeout: 10))
        drive.tap()

        // Each series on a drive is its own chart, and each one is a way in.
        let speed = app.buttons["section-card-speed"]
        scrollTo(speed, in: app)
        XCTAssertTrue(speed.exists, "The chart card is tappable")
        speed.tap()

        XCTAssertTrue(app.descendants(matching: .any)["chart-explorer-plot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["chart-explorer-table"].exists, "Raw values, as a table")
        XCTAssertTrue(app.buttons["Line"].exists)
        XCTAssertTrue(app.buttons["Bar"].exists)

        app.descendants(matching: .any)["chart-explorer-plot"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["chart-clear-reading"].waitForExistence(timeout: 3))
    }

    func testAChargingRowSaysWhatItsTwoLinesMeasure() {
        let app = launch("-ui-demo", "-ui-charges")
        XCTAssertTrue(app.otherElements["charge-history-screen"].waitForExistence(timeout: 5))

        // The thumbnail used to be two unlabelled shapes. Both series are named and
        // both axes are ticked now, in the width a row has — and the row says the
        // same thing to a reader who cannot see it.
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "charge-card-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let spoken = (row.value as? String) ?? ""
        XCTAssertTrue(
            spoken.contains("battery level and charging power over time"),
            "The row must say what its chart measures. Got: \(spoken)"
        )
    }

    func testAChargingSessionDetailNamesBothAxes() {
        let app = launch("-ui-demo", "-ui-charges")
        XCTAssertTrue(app.otherElements["charge-history-screen"].waitForExistence(timeout: 5))
        let session = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "charge-card-")
        ).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()

        // The legend is one combined element, which is right for VoiceOver: two
        // swatches read as two orphaned words otherwise.
        // Each swatch is its own combined element — right for VoiceOver, where two
        // loose words would read as nothing.
        let legend = app.staticTexts["Legend: Battery level (%)"]
        scrollTo(legend, in: app)
        XCTAssertTrue(legend.exists, "The level series is named")
        XCTAssertTrue(app.staticTexts["Legend: Charging power (kW)"].exists, "So is the power series")
        // And in words, for the reader who does not connect a colour to an axis.
        let explanation = app.staticTexts[
            "Time of day along the bottom; level on the left axis, power on the right."
        ]
        XCTAssertTrue(explanation.exists)
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }
}
