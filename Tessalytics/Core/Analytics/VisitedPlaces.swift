import Foundation

/// One end of a drive: when the car was there, and where "there" was.
struct VisitedEndpoint: Equatable, Sendable {
    let date: Date
    let label: String?
    let latitude: Double
    let longitude: Double
}

/// A place the car has been, with how often.
struct VisitedPlace: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let visits: Int
    let lastVisit: Date

    /// Whether this is somewhere the car returns to, rather than passed once.
    var isFrequent: Bool { visits >= 3 }
}

/// Turns drive endpoints into the places map on the home screen.
///
/// Every drive contributes two endpoints, and a car that parks in the same spot
/// nightly would otherwise stack hundreds of markers on one pin. Stops within a
/// hundred metres of each other are merged, which is coarse enough to collapse a
/// driveway and fine enough to keep two ends of a street apart.
enum VisitedPlacesModel {
    /// Two stops within this distance are the same place.
    ///
    /// Wide enough to cover a car park or a long driveway, narrow enough to keep
    /// two ends of a street apart.
    static let mergeRadiusMetres = 120.0

    static func places(from endpoints: [VisitedEndpoint], limit: Int = 80) -> [VisitedPlace] {
        guard !endpoints.isEmpty else { return [] }

        // Greedy clustering against a running centroid, rather than rounding onto
        // a fixed grid: a driveway that happens to straddle a grid boundary would
        // otherwise split into two places that are metres apart.
        var clusters: [Cluster] = []
        for endpoint in endpoints.filter(\.isPlausible) {
            if let index = clusters.firstIndex(where: { $0.contains(endpoint) }) {
                clusters[index].add(endpoint)
            } else {
                clusters.append(Cluster(endpoint))
            }
        }

        return Array(
            clusters
                .map(\.place)
                .sorted { ($0.visits, $0.lastVisit) > ($1.visits, $1.lastVisit) }
                .prefix(limit)
        )
    }

    /// The endpoints in the order they were visited.
    ///
    /// Consecutive duplicates are dropped: the end of one drive and the start of
    /// the next are the same spot, and a zero-length segment renders as a blob.
    static func route(from endpoints: [VisitedEndpoint], limit: Int = 400) -> [VisitedEndpoint] {
        let ordered = endpoints.filter(\.isPlausible).sorted { $0.date < $1.date }
        var route: [VisitedEndpoint] = []
        for endpoint in ordered {
            if let last = route.last, last.isSameSpot(as: endpoint) { continue }
            route.append(endpoint)
        }
        // Keep the most recent, which is the part of the map an owner recognises.
        return route.count > limit ? Array(route.suffix(limit)) : route
    }

    /// One place under construction, tracking its centroid as stops are added.
    private struct Cluster {
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var visits = 1
        private(set) var latest: VisitedEndpoint
        private var firstLabel: String?

        init(_ endpoint: VisitedEndpoint) {
            latitude = endpoint.latitude
            longitude = endpoint.longitude
            latest = endpoint
            firstLabel = endpoint.label?.nilIfEmpty
        }

        func contains(_ endpoint: VisitedEndpoint) -> Bool {
            metres(from: endpoint) <= VisitedPlacesModel.mergeRadiusMetres
        }

        mutating func add(_ endpoint: VisitedEndpoint) {
            let count = Double(visits)
            latitude = (latitude * count + endpoint.latitude) / (count + 1)
            longitude = (longitude * count + endpoint.longitude) / (count + 1)
            visits += 1
            if endpoint.date > latest.date { latest = endpoint }
            if firstLabel == nil { firstLabel = endpoint.label?.nilIfEmpty }
        }

        var place: VisitedPlace {
            VisitedPlace(
                // Identity from the centroid, which is stable for a given input.
                id: "\(Int(latitude * 100_000)):\(Int(longitude * 100_000))",
                // The most recent label wins: a geofence the owner added later is
                // a better name than the address recorded before it existed.
                name: latest.label?.nilIfEmpty ?? firstLabel ?? "Unnamed place",
                latitude: latitude,
                longitude: longitude,
                visits: visits,
                lastVisit: latest.date
            )
        }

        /// Equirectangular approximation, which is exact enough over a hundred
        /// metres and avoids a trigonometric call per comparison.
        private func metres(from endpoint: VisitedEndpoint) -> Double {
            let metresPerDegree = 111_320.0
            let dLatitude = (endpoint.latitude - latitude) * metresPerDegree
            let dLongitude = (endpoint.longitude - longitude) * metresPerDegree * cos(latitude * .pi / 180)
            return (dLatitude * dLatitude + dLongitude * dLongitude).squareRoot()
        }
    }
}

extension VisitedEndpoint {
    /// Rejects the null island and out-of-range values, which a missing reading
    /// otherwise plants in the Atlantic.
    var isPlausible: Bool {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return abs(latitude) > 0.0001 || abs(longitude) > 0.0001
    }

    func isSameSpot(as other: VisitedEndpoint) -> Bool {
        abs(latitude - other.latitude) < 0.0002 && abs(longitude - other.longitude) < 0.0002
    }
}

extension DriveRecord {
    /// Both ends of the drive, for whichever of them has coordinates.
    var visitedEndpoints: [VisitedEndpoint] {
        var endpoints: [VisitedEndpoint] = []
        if let latitude = startLatitude, let longitude = startLongitude, let date = startDate {
            endpoints.append(VisitedEndpoint(date: date, label: startAddress, latitude: latitude, longitude: longitude))
        }
        if let latitude = endLatitude, let longitude = endLongitude, let date = endDate ?? startDate {
            endpoints.append(VisitedEndpoint(date: date, label: endAddress, latitude: latitude, longitude: longitude))
        }
        return endpoints
    }
}
