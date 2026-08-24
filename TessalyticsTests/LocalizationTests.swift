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

    /// Traditional Chinese has its own catalogue, not the simplified one: the two
    /// differ in script and in vocabulary, and serving one to readers of the other
    /// is a worse answer than English.
    func testTraditionalChineseGetsItsOwnCatalogue() {
        for identifier in ["zh-Hant", "zh-TW", "zh-HK", "zh-Hant-MO"] {
            let rendered = Locale(identifier: identifier).appString("Software updates")
            XCTAssertEqual(rendered, "軟體更新", "\(identifier) should read traditional characters")
            XCTAssertNotEqual(
                rendered,
                Locale(identifier: "zh-Hans").appString("Software updates"),
                "\(identifier) is not simplified Chinese"
            )
        }
    }

    func testEveryShippedLanguageResolves() {
        let expected: [String: String] = [
            "de": "Einstellungen", "fr": "Réglages", "ja": "設定",
            "zh-Hans": "设置", "zh-Hant": "設定", "en": "Settings"
        ]
        for (code, settings) in expected {
            XCTAssertEqual(Locale(identifier: code).appString("Settings"), settings, code)
            XCTAssertNotNil(Bundle.main.path(forResource: code, ofType: "lproj"), code)
        }
    }

    /// A format string whose placeholders were lost or reordered in translation
    /// crashes or prints the wrong value, so every catalogue is checked against
    /// its key rather than spot-checked.
    func testEveryTranslationKeepsItsFormatPlaceholders() throws {
        let pattern = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[@%]")
        func placeholders(_ text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return pattern.matches(in: text, range: range).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }.sorted()
        }

        for code in ["de", "fr", "ja", "zh-Hans", "zh-Hant"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let table = try XCTUnwrap(
                NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String]
            )
            XCTAssertGreaterThan(table.count, 700, "\(code) should be a full catalogue")
            for (key, _) in table where key.contains("%") {
                let translated = bundle.localizedString(forKey: key, value: key, table: nil)
                XCTAssertEqual(
                    placeholders(translated), placeholders(key),
                    "\(code): placeholders changed in \"\(key)\""
                )
            }
        }
    }

    func testAnUnrelatedLanguageGetsEnglishRatherThanWhateverIsNearest() {
        for identifier in ["es-ES", "it-IT", "ko-KR"] {
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
        XCTAssertEqual(AppLanguage.traditionalChinese.title, "繁體中文")
        XCTAssertEqual(AppLanguage.german.title, "Deutsch")
        XCTAssertEqual(AppLanguage.japanese.title, "日本語")
        XCTAssertEqual(AppLanguage.english.title, "English")
        XCTAssertEqual(chinese.appString(AppLanguage.system.title), "系统")
    }

    func testTheChosenLanguageDecidesTheLocale() {
        XCTAssertNil(AppLanguage.system.localizationCode)
        XCTAssertEqual(AppLanguage.simplifiedChinese.localizationCode, "zh-Hans")
    }
}
