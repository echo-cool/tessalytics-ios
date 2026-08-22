import Foundation
import Observation

/// One thing worth remembering about how the app behaved.
struct DiagnosticEntry: Identifiable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case liveEvent = "Live event"
        case stream = "Stream"
        case request = "Request"
        case state = "State"
        case failure = "Failure"

        var symbol: String {
            switch self {
            case .liveEvent: "dot.radiowaves.left.and.right"
            case .stream: "antenna.radiowaves.left.and.right"
            case .request: "arrow.up.arrow.down"
            case .state: "car.fill"
            case .failure: "exclamationmark.triangle.fill"
            }
        }
    }

    let id = UUID()
    let date: Date
    let kind: Kind
    /// One line, for the list.
    let summary: String
    /// The whole thing — a raw event body, an error's description — for the
    /// screen that shows one entry at a time.
    let detail: String?
}

/// The debug mode's memory.
///
/// Off by default and unlocked by hand, because none of this is free: recording
/// live events means holding the text of a few hundred JSON documents while the
/// car is streaming several a second, and a driver who is not debugging anything
/// should not be paying for that.
///
/// Everything here stays on the device. The export is the one thing that leaves
/// it, and the export is the one thing that is redacted — a body held in memory
/// on the owner's own phone is the owner's own data, and stripping the
/// coordinates out of it would make the log useless for the thing it exists for.
@MainActor
@Observable
final class Diagnostics {
    /// How many entries are kept. A few minutes of a streaming drive.
    static let entryCapacity = 400
    /// The longest a single entry's detail is kept at. A `/state` body is about
    /// 1.5 kB pretty-printed; this leaves room for a much chattier server
    /// without letting one reply eat the whole log.
    static let detailCharacterLimit = 16_000

    private enum Key {
        static let unlocked = "diagnosticsUnlocked"
        static let recordsLiveEvents = "diagnosticsRecordsLiveEvents"
    }

    /// Newest first, which is the order the screen reads in.
    private(set) var entries: [DiagnosticEntry] = []
    /// Whether the hidden screens are reachable at all.
    private(set) var isUnlocked: Bool
    /// Whether every streamed event body is kept.
    private(set) var recordsLiveEvents: Bool
    /// Live events seen since launch, recorded or not — the rate is worth
    /// knowing even when the bodies are not being kept.
    private(set) var liveEventsSeen = 0
    private(set) var lastLiveEventAt: Date?
    /// Entries dropped off the end of the ring, so a truncated log says so.
    private(set) var discardedEntries = 0
    let startedAt = Date.now

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isUnlocked = defaults.bool(forKey: Key.unlocked)
        recordsLiveEvents = defaults.bool(forKey: Key.recordsLiveEvents)
    }

    // MARK: - Unlocking

    /// How many taps on the version number open the door.
    static let tapsToUnlock = 5

    func unlock() {
        isUnlocked = true
        defaults.set(true, forKey: Key.unlocked)
        record(.state, "Debug mode unlocked")
    }

    /// Leaves debug mode, and takes the recording and the log with it — someone
    /// turning this off is asking for the app to stop keeping any of it.
    func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Key.unlocked)
        setRecordsLiveEvents(false)
        clear()
    }

    func setRecordsLiveEvents(_ isRecording: Bool) {
        guard recordsLiveEvents != isRecording else { return }
        recordsLiveEvents = isRecording
        defaults.set(isRecording, forKey: Key.recordsLiveEvents)
        record(.state, isRecording ? "Started recording live events" : "Stopped recording live events")
    }

    // MARK: - Recording

    func record(_ kind: DiagnosticEntry.Kind, _ summary: String, detail: String? = nil, at date: Date = .now) {
        // Nothing is kept while the door is shut. A log nobody can read is a
        // memory cost and a privacy liability with no upside.
        guard isUnlocked else { return }
        append(DiagnosticEntry(date: date, kind: kind, summary: summary, detail: Self.truncated(detail)))
    }

    /// Notes that a live event arrived, and keeps its body when asked to.
    ///
    /// Counting happens either way: "the stream is up but nothing is arriving"
    /// and "readings are arriving and the screen is not showing them" are
    /// different problems, and the count is what separates them.
    func recordLiveEvent(body: Data, at date: Date = .now) {
        guard isUnlocked else { return }
        liveEventsSeen += 1
        lastLiveEventAt = date
        guard recordsLiveEvents else { return }
        let text = Self.prettyPrinted(body)
        append(
            DiagnosticEntry(
                date: date,
                kind: .liveEvent,
                summary: Self.headline(forEventBody: body) ?? "\(body.count) bytes",
                detail: Self.truncated(text)
            )
        )
    }

    func clear() {
        entries = []
        discardedEntries = 0
        liveEventsSeen = 0
        lastLiveEventAt = nil
    }

    private func append(_ entry: DiagnosticEntry) {
        entries.insert(entry, at: 0)
        guard entries.count > Self.entryCapacity else { return }
        discardedEntries += entries.count - Self.entryCapacity
        entries.removeLast(entries.count - Self.entryCapacity)
    }

    // MARK: - Formatting

    /// A one-line description of a `/state` event: the fields a glance at the
    /// list is looking for.
    static func headline(forEventBody body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let data = object["data"] as? [String: Any],
              let state = data["state"] as? [String: Any] else { return nil }
        var parts: [String] = []
        if let name = state["state"] as? String { parts.append(name) }
        if let driving = state["driving"] as? [String: Any] {
            if let shift = driving["shift_state"] as? String { parts.append(shift) }
            if let speed = driving["speed"] as? Double { parts.append("\(Int(speed.rounded())) speed") }
            if let power = driving["power"] as? Double { parts.append("\(Int(power.rounded())) kW") }
        }
        if let battery = state["battery"] as? [String: Any], let level = battery["level"] as? Int {
            parts.append("\(level)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Re-encodes a body with newlines and sorted keys, so a person can read it.
    /// A body that is not JSON is shown as it arrived rather than discarded.
    static func prettyPrinted(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let formatted = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return String(decoding: body, as: UTF8.self)
        }
        return String(decoding: formatted, as: UTF8.self)
    }

    static func truncated(_ text: String?) -> String? {
        guard let text, text.count > detailCharacterLimit else { return text }
        return String(text.prefix(detailCharacterLimit)) + "\n… truncated at \(detailCharacterLimit) characters"
    }
}

// MARK: - Export

extension Diagnostics {
    /// The report that leaves the device, redacted.
    ///
    /// `SecretRedactor` is applied to the whole thing rather than to each entry
    /// as it is recorded: in the app this is the owner reading their own car's
    /// data, and blanking the coordinates out of a location log would defeat the
    /// only reason to keep one. Sharing it is where the calculation changes.
    func exportText(context: [String: String] = [:], now: Date = .now) -> String {
        var lines: [String] = []
        lines.append("Tessalytics diagnostics")
        lines.append("Exported: \(ISO8601DateFormatter().string(from: now))")
        lines.append("Session started: \(ISO8601DateFormatter().string(from: startedAt))")
        lines.append("App: \(Self.appVersion)")
        lines.append("System: \(Self.systemDescription)")
        lines.append("Live events seen: \(liveEventsSeen)")
        if let lastLiveEventAt {
            lines.append("Last live event: \(ISO8601DateFormatter().string(from: lastLiveEventAt))")
        }
        lines.append("Recording live events: \(recordsLiveEvents ? "yes" : "no")")
        for key in context.keys.sorted() { lines.append("\(key): \(context[key] ?? "")") }
        if discardedEntries > 0 {
            lines.append("Note: \(discardedEntries) older entries were discarded to stay inside the log's capacity.")
        }
        lines.append("Entries: \(entries.count)")
        lines.append("")
        lines.append(String(repeating: "-", count: 60))

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Oldest first in the file: a log is read forwards.
        for entry in entries.reversed() {
            lines.append("")
            lines.append("[\(stamp.string(from: entry.date))] \(entry.kind.rawValue): \(entry.summary)")
            if let detail = entry.detail { lines.append(detail) }
        }
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    /// Writes the report where a share sheet can pick it up.
    func writeExport(context: [String: String] = [:], now: Date = .now) throws -> URL {
        let name = "tessalytics-diagnostics-\(Int(now.timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try exportText(context: context, now: now).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A status as the app understood it, for the entries that are about the
    /// app's own reading rather than about the wire.
    static func describe(_ status: VehicleStatus) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(status) else { return "Could not encode the status." }
        return truncated(String(decoding: data, as: UTF8.self)) ?? ""
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var systemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
