import SwiftUI

/// The hidden screen: what the app is actually receiving, and how to get it off
/// the phone.
///
/// Reachable only after the version number in Settings has been tapped five
/// times. Hidden not because it is dangerous but because it is noise: nothing on
/// this screen helps anyone understand their car, and everything on it helps
/// somebody understand a bug.
struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DiagnosticEntry?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var kindFilter: DiagnosticEntry.Kind?

    private var diagnostics: Diagnostics { environment.diagnostics }

    private var visibleEntries: [DiagnosticEntry] {
        guard let kindFilter else { return diagnostics.entries }
        return diagnostics.entries.filter { $0.kind == kindFilter }
    }

    var body: some View {
        TessalyticsScreen {
            List {
                recordingSection
                liveStateSection
                connectionSection
                logSection
                exportSection
                leaveSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { entry in
            SettingsSheetContainer { DiagnosticEntryView(entry: entry) }
        }
        .alert(
            "Could not export",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .accessibilityIdentifier("diagnostics-screen")
    }

    // MARK: - Sections

    private var recordingSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { diagnostics.recordsLiveEvents },
                    set: { diagnostics.setRecordsLiveEvents($0) }
                )
            ) {
                Label("Record live events", systemImage: "record.circle")
            }
            .accessibilityIdentifier("diagnostics-record-toggle")

            LabeledContent("Events seen", value: diagnostics.liveEventsSeen.formatted())
                .accessibilityIdentifier("diagnostics-event-count")
            LabeledContent("Last event", value: diagnostics.lastLiveEventAt.map(Self.time) ?? "None yet")
            LabeledContent("Entries kept", value: "\(diagnostics.entries.count) of \(Diagnostics.entryCapacity)")
        } header: {
            Label("Recording", systemImage: "waveform")
        } footer: {
            Text(
                "Keeps the body of every event the server sends, so a reading can be compared with what the app made of it. It costs memory while a car is streaming — leave it off unless you are chasing something."
            )
        }
    }

    /// The reading the app is drawing from, exactly as it holds it.
    private var liveStateSection: some View {
        Section {
            LabeledContent("State", value: environment.status?.state ?? "—")
            LabeledContent("Gear", value: environment.status?.drivingDetails?.shiftState ?? "—")
            LabeledContent("Driving (latched)", value: environment.isLiveDriving ? "Yes" : "No")
            LabeledContent("Position", value: Self.describe(environment.liveCoordinate))
            LabeledContent("Place", value: environment.livePlace.name ?? "Not resolved")
            LabeledContent("Self-driving", value: environment.status?.selfDrivingMode?.label ?? "Not reported")
            LabeledContent("Route points", value: environment.liveMapRoute.coordinates.count.formatted())
            LabeledContent("Buffer samples", value: environment.liveTelemetry.samples.count.formatted())
            if let status = environment.status {
                Button {
                    selected = DiagnosticEntry(
                        date: environment.statusFetchedAt ?? .now,
                        kind: .state,
                        summary: "Current status, as the app holds it",
                        detail: Diagnostics.describe(status)
                    )
                } label: {
                    Label("View the raw status", systemImage: "curlybraces")
                }
                .accessibilityIdentifier("diagnostics-raw-status")
            }
        } header: {
            Label("Live state", systemImage: "car.fill")
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Server", value: environment.selectedProfile?.baseURL.host() ?? "None")
            LabeledContent("Vehicle", value: environment.selectedVehicle.map { "\($0.id)" } ?? "None")
            LabeledContent("Streaming", value: environment.isStreamingLive ? "Connected" : "Not connected")
            if let message = environment.liveStreamMessage {
                LabeledContent("Stream error", value: message)
            }
            LabeledContent("Offline", value: environment.isOffline ? "Yes" : "No")
            LabeledContent("Owner API", value: environment.statusUsesOwnerAPI ? "In use" : "Not in use")
            LabeledContent("Demo mode", value: environment.isDemoMode ? "Yes" : "No")
            LabeledContent("App", value: Diagnostics.appVersion)
        } header: {
            Label("Connection", systemImage: "network")
        }
    }

    private var logSection: some View {
        Section {
            Picker("Show", selection: $kindFilter) {
                Text("All").tag(DiagnosticEntry.Kind?.none)
                ForEach(DiagnosticEntry.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(DiagnosticEntry.Kind?.some(kind))
                }
            }
            .accessibilityIdentifier("diagnostics-filter")

            if visibleEntries.isEmpty {
                Text("Nothing recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    Button { selected = entry } label: { row(entry) }
                        .buttonStyle(.plain)
                }
            }
        } header: {
            Label("Log", systemImage: "list.bullet.rectangle")
        } footer: {
            if diagnostics.discardedEntries > 0 {
                Text("\(diagnostics.discardedEntries) older entries have been discarded to stay inside the log's capacity.")
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                export()
            } label: {
                Label("Prepare an export", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("diagnostics-export")

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "paperplane.fill")
                }
                .accessibilityIdentifier("diagnostics-share")
            }

            Button(role: .destructive) {
                diagnostics.clear()
                exportURL = nil
            } label: {
                Label("Clear the log", systemImage: "trash")
            }
            .accessibilityIdentifier("diagnostics-clear")
        } header: {
            Label("Export", systemImage: "square.and.arrow.up")
        } footer: {
            Text("The exported file is redacted: tokens, VINs and coordinates are removed before it leaves this device.")
        }
    }

    private var leaveSection: some View {
        Section {
            Button(role: .destructive) {
                diagnostics.lock()
                // Leaving the screen on after turning it off would be an odd
                // place to stand: it no longer exists as far as Settings knows.
                dismiss()
            } label: {
                Label("Turn off debug mode", systemImage: "lock.fill")
            }
            .accessibilityIdentifier("diagnostics-lock")
        } footer: {
            Text("Clears the log and hides these screens again. Tap the version number five times to come back.")
        }
    }

    // MARK: - Pieces

    private func row(_ entry: DiagnosticEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .font(.caption)
                .foregroundStyle(entry.kind == .failure ? TessalyticsTheme.warning : TessalyticsTheme.steel)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                Text("\(Self.time(entry.date)) · \(entry.kind.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.detail != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }

    private func export() {
        do {
            exportURL = try diagnostics.writeExport(context: [
                "Server": environment.selectedProfile?.baseURL.host() ?? "none",
                "Vehicle": environment.selectedVehicle.map { "\($0.id)" } ?? "none",
                "Units": environment.statusUnits?.lengthSymbol ?? "unknown",
                "Demo mode": environment.isDemoMode ? "yes" : "no"
            ])
        } catch {
            exportError = error.localizedDescription
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    static func describe(_ coordinate: CoordinateDTO?) -> String {
        guard let coordinate else { return "None" }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(5))
        return "\(coordinate.latitude.formatted(format)), \(coordinate.longitude.formatted(format))"
    }
}

/// One entry, in full, with a way to get it onto the clipboard.
struct DiagnosticEntryView: View {
    let entry: DiagnosticEntry
    @State private var didCopy = false

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.summary)
                        .font(.headline)
                    Text("\(entry.date.formatted(.dateTime.hour().minute().second())) · \(entry.kind.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                TessalyticsTheme.steel.opacity(0.10),
                                in: .rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
                            )
                    } else {
                        Text("No detail was recorded for this entry.")
                            .foregroundStyle(.secondary)
                    }
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth()
            }
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail = entry.detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = detail
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier("diagnostics-copy")
                }
            }
        }
        .accessibilityIdentifier("diagnostics-entry-screen")
    }
}
