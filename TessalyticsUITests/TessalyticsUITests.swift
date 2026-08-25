import XCTest

@MainActor
final class TessalyticsUITests: XCTestCase {
    func testOnboardingSmoke() {
        let app = launch("-ui-onboarding")
        XCTAssertTrue(app.otherElements["onboarding-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Configure server"].exists)
        XCTAssertTrue(app.buttons["explore-demo"].exists)
    }

    func testOnboardingCanLaunchGeneratedDemo() {
        let app = launch("-ui-onboarding")
        let explore = app.buttons["explore-demo"]
        XCTAssertTrue(explore.waitForExistence(timeout: 5))
        explore.tap()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["demo-mode-banner"].exists)
        assertScrollingReveals(app, identifiers: ["home-driving-chart"])
        XCTAssertFalse(app.descendants(matching: .any)["direct-tesla-controls"].exists)
    }

    func testDashboardSmoke() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["vehicle-snapshot-card"].waitForExistence(timeout: 5))
        // The place is geocoded from the car's coordinate. It is deliberately not
        // the server's geofence, which names the last place a *drive* ended
        // inside one an owner had drawn — an address a parked car may have left
        // days ago, and the reason the hero kept showing a home address.
        XCTAssertTrue(
            app.staticTexts["1350 El Camino Real, Mountain View"].waitForExistence(timeout: 5),
            "A parked car shows where it is, not a state word"
        )
        // Scoped to the hero card. "Home" is a perfectly good place name elsewhere
        // on this screen — the destinations list is full of them — and what this
        // is about is the hero not naming the car's position from a geofence.
        XCTAssertFalse(
            app.otherElements["vehicle-snapshot-card"].staticTexts["Home"].exists,
            "The geofence is not the source for this"
        )
        // Two decimals: rounding the range to a whole unit made a figure that was
        // visibly falling look like one that was stuck.
        XCTAssertTrue(app.staticTexts["238.00"].exists)

        // The hero carries the battery ring, the odometer, the tyres and a week of
        // battery level. Lock state and cabin temperature moved out of it: the
        // three chips that held them restated figures already on the card, where
        // the shape of the week does not.
        //
        // Asserted through visible text rather than identifiers. The card is no
        // longer one big button — each figure is its own control now, and
        // `HeroNavigationUITests` covers where each of them leads — but reading
        // the numbers is still what this smoke test is for.
        XCTAssertTrue(app.staticTexts["78"].exists, "Battery ring shows the level")
        XCTAssertTrue(app.staticTexts["18,642.0"].exists, "Odometer sits beside the range, to a tenth")
        XCTAssertTrue(app.staticTexts["42.1"].exists, "A tyre pressure is shown at its corner")
        // The caption names the odometer axis when there is one, so the chart is
        // asserted by identifier rather than by a string that depends on data.
        XCTAssertTrue(app.descendants(matching: .any)["hero-battery-level-chart"].exists)
        assertScrollingReveals(app, identifiers: ["home-driving-chart"])

        // Every telemetry tile lives in a lazy grid below the fold, so none of
        // them is guaranteed to exist until scrolled into range.
        assertScrollingReveals(app, texts: [
            "Odometer", "18,642 mi",
            "Cabin", "21.5 °C",
            "Outside", "18 °C",
            // Lock state now lives in the vehicle-state card.
            "Locked"
        ])
    }

    /// Scrolls the current screen until every expected string has been seen.
    /// The same, for elements found by identifier rather than by their text.
    private func assertScrollingReveals(
        _ app: XCUIApplication,
        identifiers: [String],
        maximumSwipes: Int = 14,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var remaining = Set(identifiers)
        for _ in 0...maximumSwipes {
            remaining = remaining.filter { !app.descendants(matching: .any)[$0].exists }
            if remaining.isEmpty { return }
            app.swipeUp()
        }
        XCTAssertTrue(
            remaining.isEmpty,
            "Never found \(remaining.sorted().joined(separator: ", ")) while scrolling",
            file: file,
            line: line
        )
    }

    private func assertScrollingReveals(
        _ app: XCUIApplication,
        texts: [String],
        maximumSwipes: Int = 14,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var remaining = Set(texts)
        for _ in 0...maximumSwipes {
            remaining = remaining.filter { !app.staticTexts[$0].exists }
            if remaining.isEmpty { return }
            app.swipeUp()
        }
        XCTAssertTrue(
            remaining.isEmpty,
            "Never found \(remaining.sorted().joined(separator: ", ")) while scrolling",
            file: file,
            line: line
        )
    }

    func testDashboardHidesDirectControlsWithoutTokens() {
        let app = launch("-ui-demo", "-ui-owner-disconnected", "-diagnosticsUnlocked", "YES")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["direct-tesla-controls"].exists)
        XCTAssertFalse(app.buttons["owner-command-unlock"].exists)
    }

    /// The Owner API is unofficial and Tesla retires parts of it without notice,
    /// so it is not offered to owners as a feature. It lives behind the same
    /// unlock as the rest of the debug tools.
    func testDirectTeslaIsHiddenUntilDebugModeIsUnlocked() {
        let app = launch("-ui-demo", "-diagnosticsUnlocked", "NO")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        for _ in 0..<14 { app.swipeUp() }
        XCTAssertFalse(app.descendants(matching: .any)["direct-tesla-controls"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(
            app.buttons["owner-api-settings"].waitForExistence(timeout: 2),
            "Settings does not offer a connection an owner should not be relying on"
        )
    }

    func testDirectTeslaControlsRequireConfirmation() {
        let app = launch("-ui-demo", "-diagnosticsUnlocked", "YES")
        let controls = app.descendants(matching: .any)["direct-tesla-controls"]
        scrollTo(controls, in: app)
        let unlock = app.buttons["owner-command-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Send unlock?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Unlock"].exists)
    }

    func testOwnerTokenConnectionScreen() {
        let app = launch("-ui-demo", "-ui-owner-disconnected", "-diagnosticsUnlocked", "YES")
        app.tabBars.buttons["Settings"].tap()
        let ownerSettings = app.buttons["owner-api-settings"]
        XCTAssertTrue(ownerSettings.waitForExistence(timeout: 3))
        ownerSettings.tap()
        XCTAssertTrue(app.otherElements["owner-api-connection-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["owner-refresh-token"].exists)
        // One field. The access token is derived from the refresh token and
        // minted by the app, so asking for it only gave the pair a way to
        // disagree — a stale access token beside a good refresh token failed at
        // the first request instead of being replaced.
        XCTAssertFalse(
            app.secureTextFields["owner-access-token"].exists,
            "The access token is no longer something to paste"
        )
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
        let generatedDriveCard = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'drive-card-'"))
            .firstMatch
        XCTAssertTrue(generatedDriveCard.waitForExistence(timeout: 5))
    }

    /// A pushed detail screen must use the system back button.
    ///
    /// The custom control it used to draw required `navigationBarBackButtonHidden`,
    /// which also disables the interactive edge-swipe gesture — so the swipe back
    /// is asserted here too.
    func testDriveDetailPushesBackWithSystemControlAndSwipe() {
        let app = launch("-ui-demo", "-ui-drives")
        let driveCard = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'drive-card-'"))
            .firstMatch
        XCTAssertTrue(driveCard.waitForExistence(timeout: 5))
        driveCard.tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Pushed drive detail has no leading back control")

        backButton.tap()
        XCTAssertTrue(app.otherElements["drive-history-screen"].waitForExistence(timeout: 5))

        // Push again and leave via the edge-swipe gesture.
        XCTAssertTrue(driveCard.waitForExistence(timeout: 5))
        driveCard.tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(
            app.otherElements["drive-history-screen"].waitForExistence(timeout: 5),
            "Edge-swipe did not dismiss the pushed drive detail"
        )
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
        for _ in 0..<14 {
            if element.exists { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }
}
