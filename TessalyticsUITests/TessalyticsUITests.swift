import XCTest

@MainActor
final class TessalyticsUITests: XCTestCase {
    func testOnboardingSmoke() {
        let app = launch("-ui-onboarding")
        XCTAssertTrue(app.otherElements["onboarding-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Configure server"].exists)
    }

    func testDashboardSmoke() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parked at Home"].exists)
        XCTAssertTrue(app.staticTexts["238"].exists)
        XCTAssertTrue(app.staticTexts["Locked"].exists)
        XCTAssertTrue(app.staticTexts["Cabin 21.5°C"].exists)
    }

    func testDirectTeslaControlsRequireConfirmation() {
        let app = launch("-ui-demo")
        let controls = app.descendants(matching: .any)["direct-tesla-controls"]
        scrollTo(controls, in: app)
        let unlock = app.buttons["owner-command-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Send unlock?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Unlock"].exists)
    }

    func testOwnerTokenConnectionScreen() {
        let app = launch("-ui-demo", "-ui-owner-disconnected")
        app.tabBars.buttons["Settings"].tap()
        let ownerSettings = app.buttons["owner-api-settings"]
        XCTAssertTrue(ownerSettings.waitForExistence(timeout: 3))
        ownerSettings.tap()
        XCTAssertTrue(app.otherElements["owner-api-connection-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["owner-access-token"].exists)
        XCTAssertTrue(app.secureTextFields["owner-refresh-token"].exists)
        XCTAssertTrue(app.buttons["connect-owner-api"].exists)
    }

    func testPrimaryNavigationIsFlat() {
        let app = launch("-ui-demo")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 4)

        tabBar.buttons["Activity"].tap()
        XCTAssertTrue(app.otherElements["activity-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Drives"].exists)
        XCTAssertTrue(app.buttons["Charging"].exists)

        tabBar.buttons["Analysis"].tap()
        XCTAssertTrue(app.otherElements["insights-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Overview"].exists)
        XCTAssertTrue(app.buttons["Forecast"].exists)
        XCTAssertTrue(app.buttons["Battery"].exists)
    }

    func testDriveHistorySmoke() {
        let app = launch("-ui-demo", "-ui-drives")
        XCTAssertTrue(app.otherElements["drive-history-screen"].waitForExistence(timeout: 5))
    }

    func testDriveDetailUsesPlainBackControl() {
        let app = launch("-ui-demo", "-ui-drive-detail")
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    }

    func testChargeHistorySmoke() {
        let app = launch("-ui-demo", "-ui-charges")
        XCTAssertTrue(app.otherElements["charge-history-screen"].waitForExistence(timeout: 5))
    }

    func testAnalyticsDashboardSmoke() {
        let app = launch("-ui-demo", "-ui-analytics")
        XCTAssertTrue(app.otherElements["analytics-dashboard-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["daily-distance-chart"].waitForExistence(timeout: 5))
    }

    func testBatteryDashboardSmoke() {
        let app = launch("-ui-demo", "-ui-battery")
        XCTAssertTrue(app.otherElements["battery-health-screen"].waitForExistence(timeout: 5))
    }

    func testIntelligenceDashboardSmoke() {
        let app = launch("-ui-demo", "-ui-intelligence")
        XCTAssertTrue(app.otherElements["intelligence-screen"].waitForExistence(timeout: 5))
        scrollTo(app.descendants(matching: .any)["distance-forecast-chart"], in: app)
        scrollTo(app.descendants(matching: .any)["intelligence-signals"], in: app)
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }
}
