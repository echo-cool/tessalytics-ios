import Foundation
import SwiftUI

/// The language the app is shown in.
///
/// Separate from the phone's language on purpose. Someone whose phone is in
/// English may still want the car's app in Chinese, or the reverse — and on iOS
/// the per-app language setting lives several screens deep in Settings, which is
/// not where anybody looks for it.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// Follow the phone. The default, and what an app that has never been asked
    /// should do.
    case system
    case english = "en"
    case german = "de"
    case french = "fr"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: Self { self }

    /// Written in the language itself, which is the one form a reader looking for
    /// their own language can always recognise.
    var title: String {
        switch self {
        // Only "System" is translated: a language's own name is how a reader
        // finds it, so English stays "English" and Chinese stays 简体中文
        // whichever language the rest of the screen is in.
        case .system: "System"
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// The `.lproj` this language reads from, or `nil` to follow the phone.
    var localizationCode: String? {
        self == .system ? nil : rawValue
    }

    static let storageKey = "appLanguage"
}

/// Where a string is actually looked up.
///
/// The app is retrofitted rather than built localized: hundreds of user-facing
/// strings are plain `String` values handed to custom components, not
/// `LocalizedStringKey` literals SwiftUI can resolve on its own. So the English
/// text *is* the key, and anything without a translation falls back to itself.
/// That is what makes an incremental translation safe — an untranslated screen is
/// an English screen, never an empty one or a raw identifier.
extension Locale {
    /// The app's translation of an English string.
    func appString(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        return Self.bundleCache.bundle(for: self).localizedString(forKey: key, value: key, table: nil)
    }

    /// The app's translation of a sentence that has values in it.
    ///
    /// Interpolating first and looking the result up cannot work: "3 places" and
    /// "4 places" are different strings and neither is in any catalogue. The
    /// format is the key, so the words around the values are what gets
    /// translated — and a language that puts them in a different order can say so,
    /// which is the reason this is `%1$@`-capable rather than string concatenation.
    func appFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: appString(key), locale: self, arguments: arguments)
    }

    /// Caching matters: this is called for every title, subtitle and label on
    /// every screen, and building a `Bundle` from a path each time would do file
    /// system work inside a view body.
    private final class BundleCache: @unchecked Sendable {
        private var bundles: [String: Bundle] = [:]
        private let lock = NSLock()

        func bundle(for locale: Locale) -> Bundle {
            let code = Self.localizationCode(for: locale)
            lock.lock()
            defer { lock.unlock() }
            if let cached = bundles[code] { return cached }
            let resolved = Bundle.main.path(forResource: code, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? .main
            bundles[code] = resolved
            return resolved
        }

        /// Maps a locale onto one of the `.lproj` directories that ship.
        ///
        /// Anything Chinese in the simplified script reads the Chinese strings;
        /// everything else falls back to English rather than to the main bundle,
        /// so a French phone gets English rather than whatever the development
        /// region happens to resolve to.
        private static func localizationCode(for locale: Locale) -> String {
            let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
            if identifier.hasPrefix("zh") {
                // Simplified and traditional are different scripts with different
                // vocabulary, and each has its own catalogue. Region stands in for
                // script where the identifier does not name one.
                let traditional = ["Hant", "TW", "HK", "MO"]
                return traditional.contains(where: { identifier.contains($0) }) ? "zh-Hant" : "zh-Hans"
            }
            for code in ["de", "fr", "ja"] where identifier.hasPrefix(code) { return code }
            // Anything else reads English rather than whatever the development
            // region happens to resolve to.
            return "en"
        }
    }

    private static let bundleCache = BundleCache()
}

/// String lookup for code that has no SwiftUI environment to read.
///
/// Views take the locale from the environment, which is what makes a language
/// change redraw them. Model code that composes display text — a hero summary
/// built in an initialiser, an error's `errorDescription` — has no environment,
/// so it reads the choice from here instead.
///
/// Deliberately not actor-isolated. Isolating it to the main actor forced
/// `@MainActor` onto every value type that happens to produce a sentence, and
/// from there onto their tests — a presentation detail rewriting the concurrency
/// of models that are otherwise free of it. A lock around one rarely-written
/// value is the smaller thing to own.
enum AppText {
    private final class Holder: @unchecked Sendable {
        private var value: Locale = .autoupdatingCurrent
        private let lock = NSLock()

        var locale: Locale {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private static let holder = Holder()

    /// Kept in step with the environment by `AppEnvironment`.
    static var locale: Locale {
        get { holder.locale }
        set { holder.locale = newValue }
    }

    static func string(_ key: String) -> String { locale.appString(key) }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: locale.appString(key), locale: locale, arguments: arguments)
    }
}
