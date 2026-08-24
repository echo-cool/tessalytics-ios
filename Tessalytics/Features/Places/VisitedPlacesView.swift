import MapKit
import SwiftData
import SwiftUI

/// Everywhere the car has been, joined in the order it went there.
struct VisitedPlacesMap: View {
    let places: [VisitedPlace]
    /// One polyline per journey, as actually driven.
    ///
    /// Joining drive endpoints drew straight lines across the map — a route from
    /// San Jose to Modesto became a chord through the hills it went around. These
    /// come from the server's aggregated position track instead, so the line
    /// follows roads, and a separate segment per journey means the gap between
    /// two trips is never drawn as travel.
    let segments: [[CoordinateDTO]]
    /// Named markers are noise at card size, where the shape of the travel is the
    /// point; the full screen turns them on.
    var showsLabels = false
    var interactive = false

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: interactive ? .all : []) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(TessalyticsTheme.accent.opacity(0.75), lineWidth: 2)
                }
            }
            ForEach(places) { place in
                if showsLabels, place.isFrequent {
                    Marker(place.name, systemImage: "mappin", coordinate: place.coordinate)
                        .tint(TessalyticsTheme.accent)
                } else {
                    Annotation(place.name, coordinate: place.coordinate) {
                        Circle()
                            .fill(place.isFrequent ? TessalyticsTheme.accent : TessalyticsTheme.steel)
                            .frame(width: place.isFrequent ? 9 : 6)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    /// Frames every place, with a little air so pins are not on the edge.
    private var region: MKCoordinateRegion {
        let latitudes = places.map(\.latitude)
        let longitudes = places.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.35, 0.01),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.35, 0.01)
            )
        )
    }
}

extension VisitedPlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The full-screen version: a bigger map, and the places ranked by visits.
struct VisitedPlacesScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context

    @State private var places: [VisitedPlace] = []
    @State private var segments: [[CoordinateDTO]] = []
    @State private var mapSnapshot = RoutePosterSnapshot()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isRenderingSharePoster) private var isRenderingPoster

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                    pageContent
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth(TessalyticsLayout.wideReadableWidth)
            }
        }
        .navigationTitle("Places")
        .task(id: environment.historyRevision) { rebuild() }
        .shareablePage(sharePage, prepare: prepareMapSnapshot) {
            VStack(spacing: TessalyticsLayout.stackSpacing) { pageContent }
        }
    }

    @ViewBuilder private var pageContent: some View {
        if places.isEmpty {
            EmptyState(
                title: "No places yet",
                message: "Synchronized drives with coordinates appear here.",
                symbol: "map"
            )
        } else {
            map
            SectionCard("Most visited", subtitle: AppText.format("%@ places", "\(places.count)"), symbol: "mappin.circle.fill") {
                VStack(spacing: 0) {
                    ForEach(Array(places.prefix(isRenderingPoster ? 10 : 25).enumerated()), id: \.element.id) { index, place in
                        if index > 0 { Divider() }
                        PlaceRow(place: place)
                    }
                }
            }
        }
    }

    /// A live map on screen; drawn tiles in a poster, where `Map` renders blank.
    @ViewBuilder private var map: some View {
        if isRenderingPoster {
            RoutePosterMap(height: 340, snapshot: mapSnapshot.image)
        } else {
            VisitedPlacesMap(places: places, segments: segments, showsLabels: true, interactive: true)
                .frame(height: 340)
                .clipShape(.rect(cornerRadius: TessalyticsTheme.cardRadius, style: .continuous))
        }
    }

    private func prepareMapSnapshot() async {
        await mapSnapshot.load(
            segments: segments,
            pins: places.map { CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude) },
            size: CGSize(width: SharePoster<AnyView>.width - 40, height: 340),
            colorScheme: colorScheme
        )
    }

    private func sharePage() -> SharePage {
        let visits = places.map(\.visits).reduce(0, +)
        var highlights: [ShareHighlight] = [
            .init(label: "places", value: "\(places.count)"),
            .init(label: "arrivals", value: "\(visits)")
        ]
        if let top = places.first {
            highlights.append(.init(label: "most visited", value: top.name))
        }

        var sentences = [
            "\(places.count) place\(places.count == 1 ? "" : "s") "
            + "\(environment.selectedVehicle?.name?.nilIfEmpty ?? "my Tesla") has been to."
        ]
        if let top = places.first {
            sentences.append("Most often: \(top.name), \(top.visits) time\(top.visits == 1 ? "" : "s").")
        }
        sentences.append("Mapped by Tessalytics.")
        return SharePage(
            title: "Places",
            subtitle: SharePage.subtitle(car: environment.selectedVehicle?.name),
            highlights: highlights,
            summary: sentences.joined(separator: " ")
        )
    }

    private func rebuild() {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        let drives = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
        places = VisitedPlacesModel.places(from: drives.flatMap(\.visitedEndpoints))
        segments = cachedTrackSegments(serverID: profile.id, carID: vehicle.id, context: context)
    }
}

private struct PlaceRow: View {
    let place: VisitedPlace

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: place.isFrequent ? "mappin.circle.fill" : "mappin.circle")
                .foregroundStyle(place.isFrequent ? TessalyticsTheme.accent : TessalyticsTheme.steel)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(place.lastVisit.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(place.visits)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

/// Reads the cached path. Returns nothing rather than a fallback: a straight line
/// between endpoints is not the route, and drawing one would be a lie.
@MainActor
func cachedTrackSegments(serverID: UUID, carID: Int, context: ModelContext) -> [[CoordinateDTO]] {
    let key = TrackRecord.key(serverID: serverID, carID: carID)
    var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.cacheKey == key })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor).first)?.segments ?? []
}
