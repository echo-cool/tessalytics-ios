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
///
/// The wait is bounded separately from the fetch. `MKMapSnapshotter` is a round
/// trip to Apple's tile servers, and this one sits between a tap on the share
/// button and a share sheet: whatever the network is doing, the owner should get
/// their sheet. So `load` waits `budget` and then returns, while the fetch it
/// started carries on in the background and fills the cache — which is why the
/// tap after a slow one is instant rather than slow again.
@MainActor
@Observable
final class RoutePosterSnapshot {
    private(set) var image: UIImage?
    /// What `image` was drawn for, so an unchanged map is not fetched twice.
    private var renderedKey: String?
    /// The fetch in flight and the key it is for, so two `load` calls for the
    /// same map wait on one request rather than racing two.
    private var inFlight: Task<UIImage?, Never>?
    private var inFlightKey: String?
    /// Callers parked on the current fetch, each released by whichever of the
    /// fetch and its deadline gets there first.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// How long a share is willing to wait for tiles before going without them.
    ///
    /// Comfortably longer than a snapshot takes on a working connection, and far
    /// short of the fetch's own six-second ceiling — that ceiling bounds the
    /// request, this bounds the person watching a spinner.
    static let budget: Duration = .milliseconds(1_500)

    /// Fetches the tiles for this route, unless they are already in hand.
    func load(route: [CoordinateDTO], size: CGSize, colorScheme: ColorScheme) async {
        guard route.count > 1 else { return }
        await load(segments: [route], pins: [], size: size, colorScheme: colorScheme, marksEndpoints: true)
    }

    /// The same, for a map of many journeys rather than one — the places screen,
    /// where the segments are separate drives and the pins are the destinations.
    func load(
        segments: [[CoordinateDTO]],
        pins: [CoordinateDTO],
        size: CGSize,
        colorScheme: ColorScheme,
        marksEndpoints: Bool = false
    ) async {
        guard !segments.flatMap({ $0 }).isEmpty || !pins.isEmpty else { return }
        let key = Self.key(segments: segments, pins: pins, size: size, colorScheme: colorScheme)
        if key == renderedKey, image != nil { return }

        // One request per map: a second caller for the same key parks on the
        // fetch already running rather than starting another.
        if inFlightKey != key || inFlight == nil {
            inFlight = Task { @MainActor [weak self] in
                let produced = await Self.snapshot(
                    segments: segments,
                    pins: pins,
                    size: size,
                    colorScheme: colorScheme,
                    marksEndpoints: marksEndpoints
                )
                guard let self, self.inFlightKey == key else { return produced }
                self.inFlight = nil
                self.inFlightKey = nil
                // A failed fetch leaves the last good map in place rather than
                // blanking it. A slightly older picture of where the car is
                // beats a grey panel saying there isn't one.
                if let produced {
                    self.image = produced
                    self.renderedKey = key
                }
                self.releaseWaiters()
                return produced
            }
            inFlightKey = key
        }

        await waitForFetch(upTo: Self.budget)
    }

    /// Returns when the fetch lands or when the budget runs out, whichever comes
    /// first — and leaves the fetch running either way.
    ///
    /// Not a `TaskGroup` race against `task.value`. A `Task<_, Never>` cannot be
    /// interrupted by cancelling whoever is awaiting it, so the group waited out
    /// the whole fetch and the budget did nothing at all. A continuation the
    /// fetch resumes, with a timer that resumes it instead if the fetch is slow,
    /// actually lets go — which is the entire point, because the fetch has to
    /// carry on and fill the cache for the next tap.
    private func waitForFetch(upTo budget: Duration) async {
        let id = UUID()
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: budget)
            self?.release(id)
        }
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
        timeout.cancel()
    }

    /// Resumes one waiter, exactly once — removal from the dictionary is what
    /// makes the timer and the fetch safe to race.
    private func release(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending.values { continuation.resume() }
    }

    /// Identifies a map closely enough to reuse one, loosely enough to keep
    /// reusing it.
    ///
    /// Coordinates are rounded to about a metre. A parked car's reported position
    /// wanders by less than that between readings, and comparing the raw values
    /// meant every share refetched tiles for a map that had not moved.
    private static func key(
        segments: [[CoordinateDTO]],
        pins: [CoordinateDTO],
        size: CGSize,
        colorScheme: ColorScheme
    ) -> String {
        func rounded(_ coordinates: [CoordinateDTO]) -> String {
            coordinates
                .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
                .joined(separator: ";")
        }
        return [
            segments.map(rounded).joined(separator: "|"),
            rounded(pins),
            "\(Int(size.width))x\(Int(size.height))",
            colorScheme == .dark ? "dark" : "light",
        ].joined(separator: "#")
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

