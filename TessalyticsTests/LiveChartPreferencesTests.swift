import XCTest
@testable import Tessalytics

final class LiveChartPreferencesTests: XCTestCase {
    func testTheDefaultsAreTheOnesTheHomeScreenShipsWith() {
        let preferences = LiveChartPreferences.decode(
            metrics: LiveChartPreferences.defaultEncodedMetrics,
            windowMinutes: LiveChartPreferences.defaultWindowMinutes
        )
        XCTAssertEqual(preferences.metrics, [.speed, .power])
        XCTAssertEqual(preferences.windowMinutes, 5)
        XCTAssertEqual(preferences.window, 300)
    }

    func testAChoiceSurvivesBeingWrittenAndReadBack() {
        let chosen = LiveChartPreferences(metrics: [.elevation, .batteryLevel], windowMinutes: 10)
        let restored = LiveChartPreferences.decode(metrics: chosen.encodedMetrics, windowMinutes: 10)
        XCTAssertEqual(restored, chosen)
    }

    func testChartsAppearInDeclarationOrderWhateverOrderTheyWereChosenIn() {
        let preferences = LiveChartPreferences(metrics: [.elevation, .speed, .batteryLevel, .power])
        XCTAssertEqual(preferences.metrics, [.speed, .power, .batteryLevel, .elevation])
    }

    func testDuplicatesAreCollapsed() {
        let preferences = LiveChartPreferences(metrics: [.speed, .speed, .power, .speed])
        XCTAssertEqual(preferences.metrics, [.speed, .power])
    }

    func testAnUnknownStoredMetricIsDroppedRatherThanDefaulted() {
        // A value from a later build, or a hand-edited defaults file. Silently
        // substituting speed would show a chart nobody asked for.
        let preferences = LiveChartPreferences.decode(metrics: "speed,tyrePressure,,power", windowMinutes: 5)
        XCTAssertEqual(preferences.metrics, [.speed, .power])
    }

    func testChoosingNoChartsIsAChoice() {
        // Somebody driving with the phone on a mount may well want the figures and
        // nothing else. Empty must not silently mean "never set".
        let preferences = LiveChartPreferences.decode(metrics: "", windowMinutes: 5)
        XCTAssertTrue(preferences.metrics.isEmpty)
        XCTAssertEqual(preferences.encodedMetrics, "")
    }

    func testAWindowOutsideTheOfferedChoicesFallsBackRatherThanBeingHonoured() {
        XCTAssertEqual(LiveChartPreferences.decode(metrics: "speed", windowMinutes: 0).windowMinutes, 5)
        XCTAssertEqual(LiveChartPreferences.decode(metrics: "speed", windowMinutes: 9_999).windowMinutes, 5)
        XCTAssertEqual(LiveChartPreferences.decode(metrics: "speed", windowMinutes: -3).windowMinutes, 5)
    }

    func testEveryOfferedWindowIsAccepted() {
        for minutes in LiveChartPreferences.windowChoices {
            XCTAssertEqual(LiveChartPreferences.decode(metrics: "speed", windowMinutes: minutes).windowMinutes, minutes)
        }
    }

    func testEveryOfferedWindowFitsInsideTheBufferItReadsFrom() {
        // Offering a twenty-minute chart over a fifteen-minute buffer would draw a
        // window that is silently shorter than it says it is.
        for minutes in LiveChartPreferences.windowChoices {
            XCTAssertLessThanOrEqual(TimeInterval(minutes) * 60, LiveTelemetryBuffer.window)
        }
    }

    func testTogglingOneChartLeavesTheRestAlone() {
        var preferences = LiveChartPreferences(metrics: [.speed, .power], windowMinutes: 10)
        preferences = preferences.setting(.batteryLevel, enabled: true)
        XCTAssertEqual(preferences.metrics, [.speed, .power, .batteryLevel])
        XCTAssertEqual(preferences.windowMinutes, 10, "The window is not the toggle's business")

        preferences = preferences.setting(.power, enabled: false)
        XCTAssertEqual(preferences.metrics, [.speed, .batteryLevel])

        // Turning off something already off is not an error.
        preferences = preferences.setting(.power, enabled: false)
        XCTAssertEqual(preferences.metrics, [.speed, .batteryLevel])
    }

    func testEveryMetricCanReadItsFigureOutOfASample() {
        let sample = LiveTelemetrySample(
            id: 0, date: .now, speed: 63, power: -18, level: 62,
            odometer: 12_000, latitude: 37, longitude: -122, elevation: 42
        )
        XCTAssertEqual(LiveChartMetric.speed.reading(of: sample), 63)
        XCTAssertEqual(LiveChartMetric.power.reading(of: sample), -18)
        XCTAssertEqual(LiveChartMetric.batteryLevel.reading(of: sample), 62)
        XCTAssertEqual(LiveChartMetric.elevation.reading(of: sample), 42)
        for metric in LiveChartMetric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.symbol.isEmpty)
        }
    }
}
