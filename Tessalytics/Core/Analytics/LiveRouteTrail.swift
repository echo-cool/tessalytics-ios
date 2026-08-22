import Foundation

/// The route drawn on the live map, held still between readings.
///
/// The route used to be rebuilt from the buffer on every render: the samples were
/// thinned by taking every *n*th of them, where *n* grew with the buffer. One
/// extra reading could change *n* from 2 to 3, which replaces every point on the
/// map with a different one — the whole line jumps, and at two or three readings
/// a second that reads as a flashing route rather than a moving car.
///
/// So the route is stored rather than derived, and thinned by distance instead of
/// by index. A point that has been drawn stays drawn in the same place, new
/// positions are appended to the end, and `revision` changes only when the line
/// actually differs — which is what lets the map skip rebuilding an overlay that
/// has not moved.
struct LiveRouteTrail: Equatable, Sendable {
    /// How far apart two points must be to both be worth drawing, in degrees.
    /// Roughly ten metres, which is under a pixel on a map framing a whole drive.
    static let minimumSeparation = 0.0001
    /// The most points the line is ever drawn with.
    static let maximumPoints = 1_500

    private(set) var coordinates: [CoordinateDTO] = []
    /// Bumped only when `coordinates` changed. A map can key its overlay on this
    /// and rebuild nothing while the car sits at a light.
    private(set) var revision = 0

    var isEmpty: Bool { coordinates.isEmpty }

    /// Rebuilds the route from the fetched path and the streamed positions,
    /// leaving it untouched when the result is the same line as before.
    mutating func update(seed: [CoordinateDTO], live: [CoordinateDTO]) {
        let next = Self.decimated(LiveRoutePath.joined(seed: seed, live: live))
        guard next != coordinates else { return }
        coordinates = next
        revision &+= 1
    }

    mutating func reset() {
        guard !coordinates.isEmpty else { return }
        coordinates = []
        revision &+= 1
    }

    /// Drops points closer together than the map can tell apart.
    ///
    /// Widening the separation is the only way this ever discards a point that
    /// survived a previous pass, and it takes a doubling of the route's length to
    /// do it — where index striding reshuffled the whole line every few seconds.
    static func decimated(_ points: [CoordinateDTO], budget: Int = maximumPoints) -> [CoordinateDTO] {
        var separation = minimumSeparation
        var kept = reduced(points, separation: separation)
        // Bounded: each pass halves the point count at worst, so a route of any
        // length reaches the budget in a few dozen doublings.
        while kept.count > budget, separation < 1 {
            separation *= 2
            kept = reduced(points, separation: separation)
        }
        return kept
    }

    private static func reduced(_ points: [CoordinateDTO], separation: Double) -> [CoordinateDTO] {
        guard let first = points.first else { return [] }
        let threshold = separation * separation
        var kept = [first]
        for point in points.dropFirst() {
            let anchor = kept[kept.count - 1]
            let latitude = point.latitude - anchor.latitude
            let longitude = point.longitude - anchor.longitude
            if latitude * latitude + longitude * longitude >= threshold { kept.append(point) }
        }
        // The end of the line is where the car is. Rounding it back to the last
        // point far enough away would leave the route trailing behind the pin.
        if let last = points.last, kept[kept.count - 1] != last { kept.append(last) }
        return kept
    }
}
