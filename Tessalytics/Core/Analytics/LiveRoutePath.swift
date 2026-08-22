import Foundation

/// The route of the drive in progress, assembled from the two things that know
/// part of it.
///
/// Neither source is enough alone. The server has the path from the start of the
/// drive but is asked for it once, so it stops at the moment it was fetched. The
/// stream has every reading since, but only since the phone was listening — a
/// drive joined halfway through starts with nothing behind the car.
enum LiveRoutePath {
    /// Joins the fetched path to the readings that arrived after it.
    ///
    /// The two overlap, and time cannot arbitrate: the fetched path carries
    /// positions and no timestamps. So the join is made where the live readings
    /// pass closest to the fetched path's last point, and only what follows is
    /// appended. Drawing the overlap twice would send the route back down the road
    /// it just came up.
    static func joined(seed: [CoordinateDTO], live: [CoordinateDTO]) -> [CoordinateDTO] {
        guard let anchor = seed.last else { return live }
        guard !live.isEmpty else { return seed }

        var nearest = 0
        var shortest = Double.greatestFiniteMagnitude
        for (index, point) in live.enumerated() {
            let distance = squaredDistance(point, anchor)
            // Strictly closer, so a car standing at a light — which reports the
            // same position over and over — joins at the first of those readings
            // rather than the last.
            if distance < shortest {
                shortest = distance
                nearest = index
            }
        }
        guard nearest + 1 < live.count else { return seed }
        return seed + live[(nearest + 1)...]
    }

    /// Degrees squared. Only ever compared with another value from here, so the
    /// convergence of the meridians does not need correcting for.
    private static func squaredDistance(_ one: CoordinateDTO, _ other: CoordinateDTO) -> Double {
        let latitude = one.latitude - other.latitude
        let longitude = one.longitude - other.longitude
        return latitude * latitude + longitude * longitude
    }
}
