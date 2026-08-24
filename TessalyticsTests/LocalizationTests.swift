import XCTest
@testable import Tessalytics

/// The app was retrofitted rather than built localized: the English text is the
/// key, so what matters is that lookup resolves, that a missing key degrades to
/// English rather than to nothing, and that the catalogue does not translate data
/// that merely happens to read like interface text.
final class LocalizationTests: XCTestCase {
    private let chinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    func testChineseResolvesFromTheShippedCatalogue() {
        XCTAssertEqual(chinese.appString("Settings"), "设置")
        XCTAssertEqual(chinese.appString("Battery health"), "电池健康")
        XCTAssertEqual(chinese.appString("Send to car"), "发送到车辆")
    }

    func testEnglishIsARealLocalizationRatherThanAFallthrough() {
        // Without an en.lproj the in-app switch could select Chinese but never
        // put English back, because there would be nothing to switch to.
        XCTAssertEqual(english.appString("Settings"), "Settings")
        XCTAssertNotNil(Bundle.main.path(forResource: "en", ofType: "lproj"))
        XCTAssertNotNil(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    }

    /// The property that makes an incomplete translation safe. A screen nobody
    /// has translated is an English screen, never an empty one.
    func testAnUntranslatedStringFallsBackToItself() {
        let unknown = "Some string that is deliberately not in any catalogue"
        XCTAssertEqual(chinese.appString(unknown), unknown)
        XCTAssertEqual(chinese.appString(""), "")
    }

    /// Traditional Chinese is a different script and is not translated. Serving
    /// it simplified characters would be worse than serving it English.
    func testTraditionalChineseIsNotServedSimplifiedCharacters() {
        for identifier in ["zh-Hant", "zh-TW", "zh-HK", "zh-Hant-MO"] {
            XCTAssertEqual(
                Locale(identifier: identifier).appString("Settings"),
                "Settings",
                "\(identifier) is not a translation this app has"
            )
        }
    }

    func testAnUnrelatedLanguageGetsEnglishRatherThanWhateverIsNearest() {
        for identifier in ["fr-FR", "de-DE", "ja-JP"] {
            XCTAssertEqual(Locale(identifier: identifier).appString("Settings"), "Settings")
        }
    }

    /// The hazard of using English as the key: a place, car or address whose name
    /// happens to match an interface string would be silently translated. The
    /// defence is the catalogue's contents, so it is the catalogue that is tested.
    func testDataLikeValuesAreNotInTheCatalogue() {
        for value in ["Home", "Office", "Downtown", "Airport", "Trailhead", "Aurora",
                      "1350 El Camino Real, Mountain View"] {
            XCTAssertEqual(
                chinese.appString(value), value,
                "\"\(value)\" reads like data; translating it would rename something real"
            )
        }
    }

    /// Two controls that read identically are worse than two in a foreign
    /// language, because neither can be told from the other.
    func testTheDestinationOrdersReadDistinctly() {
        let rendered = Set(DestinationOrder.allCases.map { chinese.appString($0.rawValue) })
        XCTAssertEqual(rendered.count, DestinationOrder.allCases.count)
    }

    func testEveryLanguageOffersItselfByItsOwnName() {
        // A reader looking for their language finds it written in it.
        XCTAssertEqual(AppLanguage.simplifiedChinese.title, "简体中文")
        XCTAssertEqual(AppLanguage.english.title, "English")
        XCTAssertEqual(chinese.appString(AppLanguage.system.title), "系统")
    }

    func testTheChosenLanguageDecidesTheLocale() {
        XCTAssertNil(AppLanguage.system.localizationCode)
        XCTAssertEqual(AppLanguage.simplifiedChinese.localizationCode, "zh-Hans")
    }
}
