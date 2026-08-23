import XCTest

/// Sending a destination is the one thing in this app that reaches out and
/// changes something about the car, so the path to the button matters as much as
/// the button.
@MainActor
final class SendToCarUITests: XCTestCase {
    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"] + arguments
        app.launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        return app
    }

    private func destinationsCard(in app: XCUIApplication) -> XCUIElement {
        scroll(to: app.descendants(matching: .any)["destinations-card"].firstMatch, in: app)
    }

    @discardableResult
    private func scroll(to element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<16 {
            if element.exists, element.isHittable { return element }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Should be reachable on the home screen")
        return element
    }

    func testTheCardIsOnTheHomeScreenWhileTheCarIsParked() {
        let app = launch()
        XCTAssertTrue(destinationsCard(in: app).exists)
    }

    func testTheCardIsNotThereWhileTheCarIsDriving() {
        // A list of places to tap through is the wrong thing to hand a driver,
        // and the car's own navigation is already running.
        let app = launch("-ui-demo-driving")
        for _ in 0..<16 { app.swipeUp() }
        XCTAssertFalse(app.descendants(matching: .any)["destinations-card"].firstMatch.exists)
    }

    /// The path an owner actually takes: no Tesla account, no Owner API, just the
    /// share sheet and the Tesla app.
    func testSendingADestinationOpensTheShareSheet() {
        let app = launch("-diagnosticsUnlocked", "NO")
        destinationsCard(in: app)
        let row = scroll(to: app.descendants(matching: .any)["destination-row"].firstMatch, in: app)
        row.tap()
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 20)
                || app.buttons["Copy"].waitForExistence(timeout: 5),
            "A destination is handed to the share sheet, where Tesla is one of the choices"
        )
    }

    func testADeveloperWithTheOwnerAPIUnlockedSendsItDirectly() {
        let app = launch("-diagnosticsUnlocked", "YES")
        destinationsCard(in: app)
        let row = scroll(to: app.descendants(matching: .any)["destination-row"].firstMatch, in: app)
        row.tap()
        // Demo mode does not talk to Tesla, so this proves the path to the
        // confirmation rather than the command itself.
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 8))
        app.alerts.buttons.firstMatch.tap()
    }

    func testTheListCanBeReorderedAndFiltered() {
        let app = launch()
        destinationsCard(in: app)

        let order = scroll(to: app.descendants(matching: .any)["destinations-order"].firstMatch, in: app)
        order.buttons["Recent"].tap()

        let filterButton = app.descendants(matching: .any)["destinations-filter-button"].firstMatch
        if filterButton.exists, filterButton.isHittable { filterButton.tap() }
        let field = scroll(to: app.textFields["destinations-filter"], in: app)
        field.tap()
        field.typeText("zzz")
        // A filter that matches nothing says so rather than quietly showing
        // everything, which would send the wrong place to a car.
        XCTAssertFalse(app.descendants(matching: .any)["destination-row"].firstMatch.exists)
    }
}

/// Pages share as a picture of themselves, from a button in the top right.
@MainActor
final class PageSharingUITests: XCTestCase {
    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo"] + arguments
        app.launch()
        return app
    }

    private func share(in app: XCUIApplication) {
        let button = app.descendants(matching: .any)["share-page"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Every shareable page has a share button top right")
        button.tap()
        // The rendered poster arrives in the system share sheet, which is a
        // separate process — its appearance is the proof the image was built.
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 20)
                || app.buttons["Copy"].waitForExistence(timeout: 5),
            "The share sheet should open with the poster in it"
        )
    }

    func testTheHomeScreenShares() {
        let app = launch()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 10))
        share(in: app)
    }

    func testBatteryHealthShares() {
        let app = launch("-ui-battery")
        XCTAssertTrue(app.otherElements["battery-health-screen"].waitForExistence(timeout: 10))
        share(in: app)
    }
}
