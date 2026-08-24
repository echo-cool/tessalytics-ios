import CoreLocation
import SwiftUI

/// The places the car goes, offered back as one tap each.
///
/// The point is to remove a step that has nothing to do with driving: opening a
/// maps app, searching for somewhere the car has been to fifty times, and sharing
/// it across. Tessalytics already knows where those places are, because it
/// recorded the car arriving at them.
///
/// Only shown while the car is parked. Handing a driver a list of destinations to
/// tap through is the wrong thing to put on a screen mid-drive, and the car's own
/// navigation is already running.
struct DestinationsCard: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.locale) private var locale

    let places: [VisitedPlace]

    @State private var order: DestinationOrder = .mostVisited
    @State private var filter = ""
    @State private var isFiltering = false
    @State private var sending: CarDestination?
    @State private var shared: ShareArtifact?
    @State private var outcome: DestinationOutcome?

    /// Where "nearest" is measured from: where the car is now, or the last place
    /// it was seen.
    private var origin: CLLocationCoordinate2D? {
        guard let point = environment.liveCoordinate ?? environment.status?.carGeodata?.location else { return nil }
        return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var destinations: [CarDestination] {
        DestinationShortlist.make(from: places, order: order, filter: filter, origin: origin)
    }

    /// Sending straight to the car needs the Owner API, which is a developer-only
    /// surface in this app. Everyone else goes through the share sheet, which is
    /// the path that works with nothing but the Tesla app installed.
    ///
    /// TeslaMate is not an alternative route for this. It is a logger: it reads
    /// the car and writes rows, and neither it nor TeslaMateApi has any endpoint
    /// that sends a command to a vehicle. The Tessalytics backend holds no Tesla
    /// token by design, so it has nothing to send one with either.
    private var canSendDirectly: Bool {
        environment.diagnostics.isUnlocked && environment.isOwnerConnected
    }

    var body: some View {
        SectionCard(
            "Send to car",
            subtitle: subtitle,
            symbol: "location.north.circle.fill",
            tint: TessalyticsTheme.accent
        ) {
            VStack(spacing: 12) {
                controls
                if destinations.isEmpty {
                    Text(
                        filter.isEmpty
                            ? "Places appear here once drives with coordinates have synced."
                            : "No place matches “\(filter)”."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                            if index > 0 { Divider() }
                            DestinationRow(
                                destination: destination,
                                order: order,
                                origin: origin,
                                units: environment.statusUnits,
                                isSending: sending == destination,
                                sendsDirectly: canSendDirectly,
                                action: { send(destination) }
                            )
                        }
                    }
                }
            }
        }
        // A container rather than a plain identifier. An identifier on a view with
        // controls inside it is inherited by every one of them, which renames the
        // sort control and the rows after the card and leaves nothing able to find
        // the button that sends a destination.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("destinations-card")
        .sheet(item: $shared) { ShareSheet(artifact: $0) }
        .alert(item: $outcome) { outcome in
            Alert(title: Text(outcome.title), message: Text(outcome.message), dismissButton: .default(Text("OK")))
        }
    }

    private var subtitle: String {
        canSendDirectly
            ? "Straight to the car's navigation"
            : "Opens the share sheet — pick Tesla"
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Order", selection: $order) {
                ForEach(DestinationOrder.allCases) { option in
                    Label(locale.appString(option.rawValue), systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("destinations-order")

            if isFiltering || !filter.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter places", text: $filter)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("destinations-filter")
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear the filter")
                    }
                }
                .font(.subheadline)
                .padding(9)
                .background(
                    TessalyticsTheme.steel.opacity(0.10),
                    in: .rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
                )
            } else {
                Button {
                    isFiltering = true
                } label: {
                    Label("Filter places", systemImage: "magnifyingglass")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("destinations-filter-button")
            }
        }
    }

    /// The share sheet, unless a developer has connected the Owner API directly.
    private func send(_ destination: CarDestination) {
        guard sending == nil else { return }
        guard canSendDirectly else {
            presentShareSheet(for: destination)
            return
        }
        sending = destination
        Task { @MainActor in
            defer { sending = nil }
            do {
                if try await environment.sendDestinationToCar(destination) {
                    outcome = .init(
                        title: "Sent to the car",
                        message: "\(destination.name) is on the car's navigation."
                    )
                    return
                }
            } catch {
                // The car was reachable and said no. Falling through to the share
                // sheet here would look like it had worked.
                outcome = .init(title: "The car refused it", message: error.localizedDescription)
                return
            }
            presentShareSheet(for: destination)
        }
    }

    /// The fallback: hand the destination to iOS and let the owner pick Tesla.
    ///
    /// The Tesla app accepts a shared map link and forwards it to the car, which
    /// is the same call this app makes directly when an account is connected — one
    /// more tap, and no Tesla credentials needed.
    private func presentShareSheet(for destination: CarDestination) {
        shared = ShareArtifact(
            image: nil,
            text: destination.shareText,
            title: destination.name
        )
    }
}

/// One place, and the button that sends it.
private struct DestinationRow: View {
    let destination: CarDestination
    let order: DestinationOrder
    let origin: CLLocationCoordinate2D?
    let units: UnitsDTO?
    let isSending: Bool
    let sendsDirectly: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: sendsDirectly ? "location.north.fill" : "square.and.arrow.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TessalyticsTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(TessalyticsTheme.accent.opacity(0.12), in: .circle)
                }
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel(destination.name)
        .accessibilityHint(sendsDirectly ? "Sends this destination to the car" : "Shares this destination")
        .accessibilityIdentifier("destination-row")
    }

    private var detail: String {
        var parts = ["\(destination.visits) visit\(destination.visits == 1 ? "" : "s")"]
        if order == .nearest, let origin {
            // Metres are what the measurement is in; the app's unit preference is
            // what the owner reads in.
            let kilometres = destination.distance(from: origin) / 1_000
            parts.append("\(ValueFormatting.distance(kilometres, units: units, digits: 1)) away")
        } else {
            parts.append("last \(destination.lastVisit.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

/// What to tell the owner once the tap has resolved.
private struct DestinationOutcome: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
