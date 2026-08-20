import MapKit
import SwiftUI
import UIKit

/// In-memory cache of rendered route images.
///
/// A scrolling history list used to host one live `Map` per row, and a dozen
/// simultaneous `MKMapView` instances is enough to stall scrolling on any
/// device. Each route is instead rasterised once by `MKMapSnapshotter` and the
/// resulting bitmap is reused, so a row costs one `Image` to draw.
@MainActor
final class RouteSnapshotCache {
    static let shared = RouteSnapshotCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    private init() {}

    func image(forKey key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, forKey key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// Static map preview of a drive route.
struct RouteSnapshotView: View {
    let route: [CoordinateDTO]
    let driveID: Int
    var height: CGFloat = 150

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    @State private var failed = false

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFillFrame()
                } else {
                    placeholder
                }
            }
            .frame(width: size.width, height: size.height)
            .task(id: cacheKey(for: size)) { await render(size: size) }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(route.count > 1 ? "Drive route preview" : "Route preview unavailable")
        .accessibilityIdentifier("drive-route-preview-\(driveID)")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TessalyticsTheme.steel.opacity(colorScheme == .dark ? 0.16 : 0.10),
                    TessalyticsTheme.accent.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: failed || route.count < 2 ? "map" : "ellipsis")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private func cacheKey(for size: CGSize) -> String {
        // Colour scheme is part of the key: the snapshot bakes in map styling.
        "\(driveID):\(route.count):\(Int(size.width))x\(Int(size.height)):\(colorScheme == .dark ? "d" : "l")"
    }

    private func render(size: CGSize) async {
        guard coordinates.count > 1 else {
            image = nil
            return
        }
        let key = cacheKey(for: size)
        if let cached = RouteSnapshotCache.shared.image(forKey: key) {
            image = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = Self.region(for: coordinates)
        options.size = size
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        let points = coordinates
        let scheme = colorScheme
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            guard !Task.isCancelled else { return }
            // Drawing happens off the main actor; only UIImage handoff comes back.
            let rendered = await Task.detached(priority: .userInitiated) {
                Self.draw(route: points, on: snapshot, size: size, colorScheme: scheme)
            }.value
            guard !Task.isCancelled else { return }
            RouteSnapshotCache.shared.store(rendered, forKey: key)
            image = rendered
        } catch {
            failed = true
        }
    }

    /// Composites the route polyline and its endpoints over the map bitmap.
    private nonisolated static func draw(
        route: [CLLocationCoordinate2D],
        on snapshot: MKMapSnapshotter.Snapshot,
        size: CGSize,
        colorScheme: ColorScheme
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (index, coordinate) in route.enumerated() {
                let point = snapshot.point(for: coordinate)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }

            // A dark casing keeps the red line legible over pale map areas.
            UIColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 6
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

            UIColor(red: 0.80, green: 0, blue: 0, alpha: 1).setStroke()
            path.lineWidth = 3.5
            path.stroke()

            if let first = route.first {
                marker(at: snapshot.point(for: first), color: UIColor(red: 0.12, green: 0.58, blue: 0.34, alpha: 1), in: context.cgContext)
            }
            if let last = route.last {
                marker(at: snapshot.point(for: last), color: UIColor(red: 0.80, green: 0, blue: 0, alpha: 1), in: context.cgContext)
            }
        }
    }

    private nonisolated static func marker(at point: CGPoint, color: UIColor, in context: CGContext) {
        let radius: CGFloat = 5.5
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)
    }

    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? 0
        let maximumLatitude = latitudes.max() ?? 0
        let minimumLongitude = longitudes.min() ?? 0
        let maximumLongitude = longitudes.max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.5, 0.012),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.5, 0.012)
            )
        )
    }
}

private extension Image {
    /// `scaledToFill` without letting the image dictate the layout size.
    func scaledToFillFrame() -> some View {
        aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
