import Foundation

/// A figure the home screen can plot against time while the car is driving.
enum LiveChartMetric: String, CaseIterable, Identifiable, Sendable {
    case speed
    case power
    case batteryLevel
    case elevation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: "Speed"
        case .power: "Power"
        case .batteryLevel: "Battery level"
        case .elevation: "Elevation"
        }
    }

    var symbol: String {
        switch self {
        case .speed: "speedometer"
        case .power: "bolt.fill"
        case .batteryLevel: "battery.75percent"
        case .elevation: "mountain.2.fill"
        }
    }

    /// The one-line explanation of what the chart is saying.
    var subtitle: String {
        switch self {
        case .speed: "Live"
        case .power: "Negative is regeneration"
        case .batteryLevel: "This drive"
        case .elevation: "This drive"
        }
    }

    func reading(of sample: LiveTelemetrySample) -> Double? {
        switch self {
        case .speed: sample.speed
        case .power: sample.power
        case .batteryLevel: sample.level
        case .elevation: sample.elevation
        }
    }
}

/// Which live charts the home screen draws, and how much of the recent past each
/// of them covers.
///
/// A driver watching power on a mount and an owner watching the battery drain on
/// a long trip want different charts, and neither wants to scroll past the other
/// one's. Both the choice and the window are the owner's to make, so this decodes
/// what was stored and — more importantly — refuses to produce nonsense from a
/// stored value that has been corrupted, downgraded from a later version, or
/// hand-edited.
struct LiveChartPreferences: Equatable, Sendable {
    /// `UserDefaults` keys. Named here so the settings screen and the dashboard
    /// cannot drift apart over a typo.
    static let metricsKey = "liveChartMetrics"
    static let windowKey = "liveChartWindowMinutes"

    static let defaultMetrics: [LiveChartMetric] = [.speed, .power]
    static let windowChoices = [2, 5, 10, 15]
    static let defaultWindowMinutes = 5

    /// What `@AppStorage` starts from before the owner has chosen anything.
    static let defaultEncodedMetrics = encode(defaultMetrics)

    var metrics: [LiveChartMetric]
    var windowMinutes: Int

    init(metrics: [LiveChartMetric] = defaultMetrics, windowMinutes: Int = defaultWindowMinutes) {
        self.metrics = Self.ordered(metrics)
        self.windowMinutes = Self.clamped(windowMinutes)
    }

    /// The chart window as the buffer measures time.
    var window: TimeInterval { TimeInterval(windowMinutes) * 60 }

    /// Reads back what `encode` wrote.
    ///
    /// An unrecognised name is dropped rather than defaulted: a metric this build
    /// does not have is not the same as the owner asking for speed. An empty
    /// selection is honoured — "no charts" is a choice somebody driving with the
    /// phone on a mount may well make.
    static func decode(metrics raw: String, windowMinutes: Int) -> LiveChartPreferences {
        var preferences = LiveChartPreferences(windowMinutes: windowMinutes)
        preferences.metrics = ordered(
            raw.split(separator: ",").compactMap { LiveChartMetric(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        )
        return preferences
    }

    static func encode(_ metrics: [LiveChartMetric]) -> String {
        ordered(metrics).map(\.rawValue).joined(separator: ",")
    }

    var encodedMetrics: String { Self.encode(metrics) }

    func contains(_ metric: LiveChartMetric) -> Bool { metrics.contains(metric) }

    func setting(_ metric: LiveChartMetric, enabled: Bool) -> LiveChartPreferences {
        var updated = metrics.filter { $0 != metric }
        if enabled { updated.append(metric) }
        return LiveChartPreferences(metrics: updated, windowMinutes: windowMinutes)
    }

    /// Declaration order, deduplicated, so the charts appear in the same order
    /// whatever order the toggles were flipped in.
    private static func ordered(_ metrics: [LiveChartMetric]) -> [LiveChartMetric] {
        LiveChartMetric.allCases.filter(metrics.contains)
    }

    private static func clamped(_ minutes: Int) -> Int {
        windowChoices.contains(minutes) ? minutes : defaultWindowMinutes
    }
}
