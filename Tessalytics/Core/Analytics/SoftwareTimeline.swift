import Foundation

/// A stretch of time the car spent on one firmware version.
///
/// TeslaMate records an *update* — the moment a version was installed. What an
/// owner actually wants to know is the other thing: how long the car then ran it,
/// and which version it was running on some day they remember. That is the gap
/// between one install and the next, which is derivable but was never derived: the
/// screen listed a version and a date and left the arithmetic to the reader.
struct SoftwareVersionPeriod: Identifiable, Equatable, Sendable {
    let id: Int
    let version: String
    /// When this version started running, which is when its install finished.
    let installedAt: Date
    /// When the next version replaced it, or nil while it is still running.
    let supersededAt: Date?

    var isCurrent: Bool { supersededAt == nil }

    /// The end of the band on a chart: the day it was replaced, or today.
    func end(now: Date = .now) -> Date { supersededAt ?? now }

    /// Whole days spent on this version, never negative.
    ///
    /// Two updates on the same day are a version that ran for part of a day, and
    /// zero is the honest answer for that — rounding it up to one would make a
    /// version the car ran for twenty minutes look like a day's use.
    func days(now: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: installedAt, to: end(now: now)).day ?? 0)
    }

    /// How long it ran, in words.
    func durationDescription(now: Date = .now) -> String {
        let days = days(now: now)
        let counted = days == 0 ? "Under a day" : "\(days) day\(days == 1 ? "" : "s")"
        return isCurrent ? "\(counted) so far" : counted
    }
}

enum SoftwareTimeline {
    /// Turns a list of installs into the periods between them.
    ///
    /// - Parameter updates: in any order; TeslaMateApi does not promise one.
    /// - Returns: newest first, which is the order the list reads in. A chart
    ///   sorts them back.
    static func periods(from updates: [FirmwareUpdateDTO], now: Date = .now) -> [SoftwareVersionPeriod] {
        // An install with no date at all cannot be placed on a timeline. The
        // install's *end* is when the version started running; its start is when
        // the car went offline to install it, which is not the same thing.
        let dated = updates
            .compactMap { update -> (id: Int, version: String, at: Date)? in
                guard let at = update.endDate?.value ?? update.startDate?.value else { return nil }
                return (update.updateId, update.reportedVersion ?? "Version not reported", at)
            }
            .sorted { $0.at < $1.at }

        let periods = dated.enumerated().map { index, install in
            SoftwareVersionPeriod(
                id: install.id,
                version: install.version,
                installedAt: install.at,
                // The next install is what ended this one. Nothing follows the
                // newest, which is the version the car is on now.
                supersededAt: index + 1 < dated.count ? dated[index + 1].at : nil
            )
        }
        return periods.reversed()
    }

    /// The span a chart should cover, or nil when there is nothing to draw.
    static func span(of periods: [SoftwareVersionPeriod], now: Date = .now) -> ClosedRange<Date>? {
        guard let earliest = periods.map(\.installedAt).min() else { return nil }
        let latest = periods.map { $0.end(now: now) }.max() ?? now
        guard latest > earliest else { return nil }
        return earliest...latest
    }

    /// The version the car was running on a given day, if these periods cover it.
    static func version(on date: Date, in periods: [SoftwareVersionPeriod], now: Date = .now) -> String? {
        periods.first { $0.installedAt <= date && date < $0.end(now: now) }?.version
    }
}

extension FirmwareUpdateDTO {
    /// The version, or nil when the server did not report one.
    var reportedVersion: String? { version?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
}
