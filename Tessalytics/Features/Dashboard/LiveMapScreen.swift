import MapKit
import SwiftUI

/// The drive in progress, given the whole screen.
///
/// The hero card's map is a thumbnail: it says the car is somewhere and moving.
/// This is the same route with room to read it — pannable, zoomable, and with the
/// live figures floating over it rather than scrolled away underneath. A driver
/// with the phone on a mount is the reader, so the numbers stay on screen and the
/// map is what changes.
struct LiveMapScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Off as soon as the map is dragged: a camera that snaps back to the car
    /// every second makes the map impossible to look ahead on.
    @State private var followsCar = true

    private var status: VehicleStatus? { environment.status }

    private var coordinate: CLLocationCoordinate2D? {
        guard let location = status?.carGeodata?.location,
              abs(location.latitude) > 0.0001 || abs(location.longitude) > 0.0001 else { return nil }
        return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var metrics: [LiveMetric] {
        LiveMetrics.expanded(
            status: status,
            buffer: environment.liveTelemetry,
            units: environment.statusUnits
        )
    }

    var body: some View {
        ZStack {
            if let coordinate {
                LiveLocationMap(
                    coordinate: coordinate,
                    heading: status?.drivingDetails?.heading,
                    route: environment.liveMapRoute,
                    isInteractive: true,
                    followsCar: followsCar
                )
                .ignoresSafeArea()
                // A drag is the only reliable statement that the reader wants to
                // look somewhere other than at the car.
                .simultaneousGesture(DragGesture().onChanged { _ in followsCar = false })
            } else {
                EmptyState(
                    title: "No position",
                    message: "The vehicle has not reported a location for this drive yet.",
                    symbol: "mappin.slash"
                )
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                readout
            }
        }
        // Contained rather than named outright: an identifier on a view wrapping
        // controls is inherited by all of them, and the close button ends up
        // called after the screen.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-map-screen")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .padding(10)
                    .background(.regularMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the map")
            .accessibilityIdentifier("live-map-close")

            if let name = environment.selectedVehicle?.name?.nilIfEmpty {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: .capsule)
            }

            Spacer(minLength: 0)

            LiveIndicator(isStreaming: environment.isStreamingLive)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: .capsule)

            Button {
                followsCar = true
            } label: {
                Image(systemName: followsCar ? "location.fill" : "location")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(followsCar ? TessalyticsTheme.accentBright : .primary)
                    .padding(10)
                    .background(.regularMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(followsCar)
            .accessibilityLabel("Follow the vehicle")
            .accessibilityIdentifier("live-map-follow")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// The figures, over the map rather than beside it.
    ///
    /// On a material rather than a solid card: the road under the panel is still
    /// worth a glance, and hiding a third of the map behind an opaque block is how
    /// a full-screen map ends up smaller than the thumbnail it was opened from.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiveMetricGrid(metrics: metrics)

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TessalyticsTheme.accentBright.opacity(0.16), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .tessalyticsReadableWidth()
        .accessibilityIdentifier("live-map-readout")
    }

    private var footnote: String {
        let updated = environment.statusFetchedAt.map { "updated at \(ValueFormatting.readingTime($0))" }
        let span = environment.liveTelemetry.span
            .map { "driving for \(ValueFormatting.duration(minutes: max(Int($0 / 60), 1)))" }
        let parts = [span, updated].compactMap { $0 }
        return parts.isEmpty ? "Waiting for vehicle data" : parts.joined(separator: " · ")
    }
}
