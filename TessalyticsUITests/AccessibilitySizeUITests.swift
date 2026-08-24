import XCTest

/// A translation is not the same length as its English, and neither is the type
/// it is set in. German runs longer than English; Japanese sets taller. At
/// accessibility sizes both meet a layout designed around neither.
///
/// What these tests can prove is that the screens still *work*: every control is
/// present, has a real size, and can be tapped. What they cannot prove is that
/// nothing is drawn over anything else — a glyph overflowing its frame onto the
/// label beside it is invisible to a query and was found by looking. Both bugs
/// this file exists because of were of that kind, so treat a green run as
/// necessary and not sufficient.
@MainActor
final class AccessibilitySizeUITests: XCTestCase {
    /// Larger than the default and short of the largest, which is where most
    /// people who need bigger type actually sit.
    private static let contentSize = "UICTContentSizeCategoryAccessibilityXL"

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-demo",
            "-appLanguage", language,
            "-UIPreferredContentSizeCategoryName", Self.contentSize
        ]
        app.launch()
        XCTAssertTrue(
            app.otherElements["dashboard-screen"].waitForExistence(timeout: 15),
            "\(language) at \(Self.contentSize) should still reach the home screen"
        )
        return app
    }

    private func assertUsable(_ element: XCUIElement, _ what: String, in language: String) {
        XCTAssertTrue(element.exists, "\(what) is missing in \(language) at accessibility size")
        guard element.exists else { return }
        // A control squeezed to nothing is present and useless.
        XCTAssertGreaterThan(element.frame.height, 12, "\(what) collapsed in \(language)")
        XCTAssertGreaterThan(element.frame.width, 12, "\(what) collapsed in \(language)")
    }

    private func scroll(to element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 where !element.exists { app.swipeUp() }
    }

    func testTheHeroFiguresSurviveGermanAtAccessibilitySize() {
        let app = launch(language: "de")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-battery"], "battery ring", in: "de")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-range"], "range", in: "de")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-odometer"], "odometer", in: "de")
    }

    func testTheHeroFiguresSurviveJapaneseAtAccessibilitySize() {
        let app = launch(language: "ja")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-battery"], "battery ring", in: "ja")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-range"], "range", in: "ja")
        assertUsable(app.descendants(matching: .any)["vehicle-snapshot-odometer"], "odometer", in: "ja")
    }

    /// Where a parked car is standing is the whole point of that line, and it
    /// used to share a row with two badges under a single-line limit — which at
    /// accessibility sizes left "1350…".
    func testTheParkedAddressIsShownInFullInBothLanguages() {
        for language in ["de", "ja"] {
            let app = launch(language: language)
            // Given the width of the card to itself, the address needs more than
            // one line's worth of height.
            // The static text specifically. An identifier on a Label is
            // inherited by the SF Symbol inside it, and `firstMatch` picks the
            // image — which has a fixed height and reports the same number
            // whether the address wrapped or was cut to "1350…".
            let text = app.staticTexts.matching(identifier: "vehicle-place").firstMatch
            XCTAssertTrue(text.exists, "The address text is missing in \(language)")
            XCTAssertGreaterThan(
                text.frame.height, 80,
                "\(language): the address should wrap to several lines, not be cut to one"
            )
        }
    }

    /// The quick links sit four across, so a translated title has a quarter of the
    /// width. "Auswertung" did not fit and was cut to "Auswer…".
    func testTheQuickLinkTilesKeepTheirFullTitles() {
        for language in ["de", "ja"] {
            let app = launch(language: language)
            let tiles = app.buttons.allElementsBoundByIndex.filter {
                $0.frame.width > 60 && $0.frame.width < 140 && $0.frame.height > 40
            }
            XCTAssertGreaterThanOrEqual(
                tiles.count, 4,
                "The four quick links should still be there in \(language)"
            )
            for tile in tiles.prefix(4) {
                XCTAssertFalse(
                    tile.label.hasSuffix("…"),
                    "\(language): \"\(tile.label)\" is truncated"
                )
            }
        }
    }

    func testTheLanguageAndUnitPickersAreUsable() {
        for language in ["de", "ja"] {
            let app = launch(language: language)
            app.tabBars.buttons.element(boundBy: 3).tap()
            let picker = app.descendants(matching: .any)["language-picker"].firstMatch
            scroll(to: picker, in: app)
            assertUsable(picker, "the language picker", in: language)
            let units = app.descendants(matching: .any)["unit-picker"].firstMatch
            scroll(to: units, in: app)
            assertUsable(units, "the unit picker", in: language)
        }
    }
}
