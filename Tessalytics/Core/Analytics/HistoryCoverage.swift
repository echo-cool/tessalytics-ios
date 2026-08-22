import Foundation

/// Whether there is enough recorded history for the derived charts to mean
/// anything, and what to say when there is not.
///
/// Half of this app is computed from weeks of drives and charges. A TeslaMate
/// install that is hours old can supply almost none of it, so the first
/// impression is a screen of blank panels — which reads as broken rather than as
/// new. The fix is waiting, and waiting is not something anyone guesses at.
enum HistoryCoverage {
    /// Below either of these, the derived charts are still filling up.
    static let settledDays = 14
    static let settledEvents = 8

    /// A description of what has been recorded, or nil once there is plainly
    /// enough for the charts to stand on.
    ///
    /// Judged on both the span and the count. A car driven twice a day for a
    /// fortnight is ready; one driven twice in a fortnight is not, and the span
    /// alone cannot tell them apart.
    static func summary(of dates: [Date], now: Date = .now) -> String? {
        guard let oldest = dates.min() else {
            return "No completed drives or charges recorded yet."
        }
        let days = Calendar.current.dateComponents([.day], from: oldest, to: now).day ?? 0
        guard days < settledDays || dates.count < settledEvents else { return nil }

        let events = "\(dates.count) drive\(dates.count == 1 ? "" : "s") and charge\(dates.count == 1 ? "" : "s")"
        return days < 1
            ? "\(events), all from today."
            : "\(events) over \(days) day\(days == 1 ? "" : "s")."
    }
}
