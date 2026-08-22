import XCTest

/// The route into signing a browser in.
///
/// The button's *placement* is the thing worth a test: it is used sitting in the
/// car with a code already counting down on the centre screen, so it has to be one
/// tap from the first screen the app opens on — not somewhere in Settings. A
/// refactor that quietly moves it into a menu is a regression this catches.
@MainActor
final class WebPairingUITests: XCTestCase {
    func testTheStatusScreenOffersToSignABrowserIn() {
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))

        let scan = app.buttons["scan-pairing-code"]
        XCTAssertTrue(scan.waitForExistence(timeout: 3), "The scan button belongs on the Status screen")

        // Top left specifically: that is where someone looks for it, and the
        // vehicle picker owns the trailing side.
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(scan.frame.midX, window.midX, "The scan button sits at the leading edge")
        XCTAssertLessThan(scan.frame.midY, window.height / 4, "…and in the navigation bar")
    }

    func testDemoModeExplainsThereIsNoServerToPairWith() {
        // Demo mode has no backend, so the sheet must say so rather than open a
        // camera that can only fail.
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        app.buttons["scan-pairing-code"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["web-pairing-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["No server connected"].waitForExistence(timeout: 3),
            "A demo install has nothing to sign a browser in to"
        )
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 3))
    }

    func testDemoSettingsDoesNotOfferPairedBrowsers() {
        // "Paired browsers" lives in Settings' live-data section, which demo mode
        // hides along with Direct Tesla and live charts: there is no server, so
        // there is nothing signed in to it and nothing to sign in. The route that
        // *is* offered in demo mode — the Status button — explains that itself,
        // which the test above covers.
        let app = launch("-ui-demo")
        XCTAssertTrue(app.otherElements["dashboard-screen"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-achievements"].waitForExistence(timeout: 5))


        for _ in 0..<8 {
            XCTAssertFalse(
                app.buttons["paired-browsers-settings"].exists,
                "Demo mode has no server, so it must not offer to manage sessions on one"
            )
            app.swipeUp()
        }
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
