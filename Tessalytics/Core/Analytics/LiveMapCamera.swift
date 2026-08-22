import Foundation

/// What the live map is looking at: a centre and a span, in degrees.
struct LiveMapFraming: Equatable, Sendable {
    var centerLatitude: Double
    var centerLongitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double
}

/// Decides where the live map's camera points, and — as importantly — when it
/// should bother moving.
///
/// The camera used to be reset on every reading, each time with a six-tenths of a
/// second animation. Readings arrive two or three times a second, so every
/// animation was cut off by the next one and the map never settled. Framing is
/// quantised here instead: the span rounds up to a step, and the centre only
/// follows once the car has actually gone somewhere.
enum LiveMapCamera {
    /// The closest view the camera ever takes, in degrees.
    static let minimumSpan = 0.01
    /// The widest. Past this the car is a dot on a county and the route has
    /// stopped saying anything at this size, so a long drive frames its recent
    /// miles rather than all of them.
    static let maximumSpan = 0.32
    /// Zoom steps, in degrees.
    static let spanStep = 0.005
    /// How far the centre must move before the camera follows, in degrees.
    /// About forty metres — a second or so of motorway driving.
    static let recentreThreshold = 0.0004

    /// Frames the route and the car together, as the route grows.
    static func framing(
        car: CoordinateDTO,
        trail: [CoordinateDTO],
        maximumSpan: Double = maximumSpan
    ) -> LiveMapFraming {
        var minimumLatitude = car.latitude, maximumLatitude = car.latitude
        var minimumLongitude = car.longitude, maximumLongitude = car.longitude

        // Walked newest first, so what a long route loses is the beginning of the
        // drive rather than the road the car is on.
        for point in trail.reversed() {
            let latitude = (min(minimumLatitude, point.latitude), max(maximumLatitude, point.latitude))
            let longitude = (min(minimumLongitude, point.longitude), max(maximumLongitude, point.longitude))
            guard latitude.1 - latitude.0 <= maximumSpan,
                  longitude.1 - longitude.0 <= maximumSpan else { break }
            (minimumLatitude, maximumLatitude) = latitude
            (minimumLongitude, maximumLongitude) = longitude
        }

        // The car's own position is in the box by construction, so the centre is
        // the box's: weighting it towards the car pushes the road the car has just
        // come down off the bottom of the frame.
        return LiveMapFraming(
            centerLatitude: (minimumLatitude + maximumLatitude) / 2,
            centerLongitude: (minimumLongitude + maximumLongitude) / 2,
            latitudeDelta: stepped(maximumLatitude - minimumLatitude, maximum: maximumSpan),
            longitudeDelta: stepped(maximumLongitude - minimumLongitude, maximum: maximumSpan)
        )
    }

    /// Whether the camera has drifted far enough from what it is showing to be
    /// worth animating again.
    static func shouldMove(from current: LiveMapFraming?, to next: LiveMapFraming) -> Bool {
        guard let current else { return true }
        if current.latitudeDelta != next.latitudeDelta || current.longitudeDelta != next.longitudeDelta { return true }
        let latitude = abs(current.centerLatitude - next.centerLatitude)
        let longitude = abs(current.centerLongitude - next.centerLongitude)
        return max(latitude, longitude) >= recentreThreshold
    }

    /// A span with room around the route, rounded up to a step and held between
    /// the closest and widest views.
    ///
    /// Stepped rather than fitted exactly: refitting on every reading makes the
    /// map breathe, and a map that rescales continuously is harder to read than
    /// one that is occasionally a little loose. The steps are even rather than
    /// doublings, so loose costs half a kilometre of margin instead of half the
    /// frame.
    static func stepped(_ extent: Double, maximum: Double = maximumSpan) -> Double {
        let padded = extent * 1.35
        return min(maximum, max(minimumSpan, (padded / spanStep).rounded(.up) * spanStep))
    }
}
