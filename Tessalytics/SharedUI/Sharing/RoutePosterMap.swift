import MapKit
import os
import SwiftUI

/// A route drawn as a picture rather than as a map view.
///
/// `ImageRenderer` walks SwiftUI's own layers, and MapKit is not one of them: a
/// `Map` in a rendered poster comes out as an empty rectangle. Since the route is
/// the most worthwhile thing on several of these pages, the poster asks
/// `MKMapSnapshotter` for the tiles and draws the line over them itself.
///
/// Asynchronous, and deliberately so — the snapshot is fetched while the share
/// button spins, not while the page is being read.
@MainActor
@Observable
final class RoutePosterSnapshot {
    private(set) var image: UIImage?
    private var rendered: [CoordinateDTO] = []

    private var renderedPins: [CoordinateDTO] = []

    /// Fetches the tiles for this route, unless they are already in hand.
    func load(route: [CoordinateDTO], size: CGSize, colorScheme: ColorScheme) async {
        guard route.count > 1, route != rendered else { return }
        rendered = route
        image = await Self.snapshot(route: route, size: size, colorScheme: colorScheme)
    }

    /// The same, for a map of many journeys rather than one — the places screen,
    /// where the segments are separate drives and the pins are the destinations.
    func load(
        segments: [[CoordinateDTO]],
        pins: [CoordinateDTO],
        size: CGSize,
        colorScheme: ColorScheme
    ) async {
        let flattened = segments.flatMap { $0 }
        guard !flattened.isEmpty || !pins.isEmpty else { return }
        guard flattened != rendered || pins != renderedPins else { return }
        rendered = flattened
        renderedPins = pins
        image = await Self.snapshot(
            segments: segments,
            pins: pins,
            size: size,
            colorScheme: colorScheme
        )
    }

    /// The tiles for a route, with the route drawn over them.
    nonisolated static func snapshot(
        route: [CoordinateDTO],
        size: CGSize,
        colorScheme: ColorScheme
    ) async -> UIImage? {
        await snapshot(segments: [route], pins: [], size: size, colorScheme: colorScheme, marksEndpoints: true)
    }

    nonisolated static func snapshot(
        segments: [[CoordinateDTO]],
        pins: [CoordinateDTO],
        size: CGSize,
        colorScheme: ColorScheme,
        marksEndpoints: Bool = false
    ) async -> UIImage? {
        let route = segments.flatMap { $0 } + pins
        guard let region = region(for: route) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )

        // Bounded, because this sits between a tap and a share sheet. A tile
        // server that is slow or unreachable would otherwise leave the button
        // spinning with nothing to say, and a poster with a plain panel where the
        // map should be is a better outcome than one that never arrives.
        guard let boxed = await Self.snapshot(with: options, timeout: 6) else { return nil }
        let snapshot = boxed.snapshot

        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)

            let drawn = segments.map { segment in
                segment.map {
                    snapshot.point(for: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                }
            }

            let path = UIBezierPath()
            for points in drawn where points.count > 1 {
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            if !path.isEmpty {
                // Drawn twice: a dark casing under the colour, so the line reads on
                // both a pale and a dark map without either being tinted to suit it.
                UIColor.black.withAlphaComponent(0.20).setStroke()
                path.lineWidth = 7
                path.stroke()
                UIColor(TessalyticsTheme.accentBright).setStroke()
                path.lineWidth = 4
                path.stroke()
            }

            // Where it started and where it ended.
            if marksEndpoints, let points = drawn.first, points.count > 1 {
                mark(points[0], colour: UIColor(TessalyticsTheme.positive), in: context.cgContext)
                mark(points[points.count - 1], colour: UIColor(TessalyticsTheme.accent), in: context.cgContext)
            }

            for pin in pins {
                let point = snapshot.point(
                    for: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                )
                mark(point, colour: UIColor(TessalyticsTheme.accent), in: context.cgContext)
            }
        }
    }

    /// A snapshot, handed across a task boundary.
    ///
    /// `MKMapSnapshotter.Snapshot` is not `Sendable`. Exactly one task reads this
    /// one, after the callback that made it has returned, so vouching for it here
    /// is honest rather than a way around the checker.
    struct SnapshotBox: @unchecked Sendable {
        let snapshot: MKMapSnapshotter.Snapshot
        init(_ snapshot: MKMapSnapshotter.Snapshot) { self.snapshot = snapshot }
    }

    /// Takes a snapshot, giving up after a deadline.
    ///
    /// `MKMapSnapshotter` has no timeout of its own and waits on the network for
    /// as long as the network takes — and this sits between a tap and a share
    /// sheet. A poster with a plain panel where the map should be is a better
    /// outcome than one that never arrives.
    ///
    /// Written around the callback rather than the `async` overload because
    /// neither `Options` nor `Snapshot` is `Sendable`, so they cannot cross the
    /// task boundary a `TaskGroup` race would need.
    private nonisolated static func snapshot(
        with options: MKMapSnapshotter.Options,
        timeout: TimeInterval
    ) async -> SnapshotBox? {
        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            func finish(_ snapshot: SnapshotBox?) {
                let shouldResume = hasResumed.withLock { resumed -> Bool in
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
                if shouldResume { continuation.resume(returning: snapshot) }
            }
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                finish(snapshot.map(SnapshotBox.init))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                snapshotter.cancel()
                finish(nil)
            }
        }
    }

    private nonisolated static func mark(_ point: CGPoint, colour: UIColor, in context: CGContext) {
        let radius: CGFloat = 6
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: rect.insetBy(dx: -2, dy: -2))
        context.setFillColor(colour.cgColor)
        context.fillEllipse(in: rect)
    }

    /// A region holding the whole route, with a margin so the line does not run
    /// into the edge of the frame.
    nonisolated static func region(for route: [CoordinateDTO]) -> MKCoordinateRegion? {
        guard !route.isEmpty else { return nil }
        let latitudes = route.map(\.latitude)
        let longitudes = route.map(\.longitude)
        guard let minimumLatitude = latitudes.min(), let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(), let maximumLongitude = longitudes.max() else { return nil }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                // A floor as well as a margin: a drive around one car park has a
                // span of almost nothing, and a map zoomed to that is unreadable.
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.35, 0.004),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.35, 0.004)
            )
        )
    }
}

/// Draws the route: a live map on screen, a snapshot in a poster.
struct RoutePosterMap: View {
    @Environment(\.isRenderingSharePoster) private var isRenderingPoster
    @Environment(\.colorScheme) private var colorScheme

    /// Only used on screen. A page whose live map is something other than a route
    /// — the places map, the car's own location — leaves this empty and supplies
    /// the snapshot instead.
    var route: [CoordinateDTO] = []
    var height: CGFloat = 200
    /// Supplied by the page, which loads it before the poster is drawn.
    var snapshot: UIImage?

    var body: some View {
        Group {
            if isRenderingPoster {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Better than an empty rectangle, which is what a `Map` draws
                    // here and reads as a bug.
                    ZStack {
                        TessalyticsTheme.steel.opacity(0.12)
                        Label("Route not available in this image", systemImage: "map")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                RouteSnapshotView(route: route, driveID: 0, height: height)
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous))
    }
}

