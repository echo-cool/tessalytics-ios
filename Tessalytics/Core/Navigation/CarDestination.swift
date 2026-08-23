import CoreLocation
import Foundation

/// Somewhere the car has been, offered back as somewhere to go.
///
/// The point of this type is that a place the car *drove to* is a better
/// destination than a place a search box guessed: it is an address the car has
/// already parked at, so it is reachable, and the owner recognises it.
struct CarDestination: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let visits: Int
    let lastVisit: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(place: VisitedPlace) {
        id = place.id
        name = place.name
        latitude = place.latitude
        longitude = place.longitude
        visits = place.visits
        lastVisit = place.lastVisit
    }

    init(id: String, name: String, latitude: Double, longitude: Double, visits: Int, lastVisit: Date) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.visits = visits
        self.lastVisit = lastVisit
    }

    /// What actually gets sent to the car.
    ///
    /// A coordinate rather than the name, wrapped in the maps link an Android
    /// share intent would carry. The car re-geocodes whatever it is given, and a
    /// name like "Home" or "Whole Foods Market" geocodes to whichever one the
    /// car's search decides on — which is not necessarily the one the car has
    /// been parking at. The coordinate cannot be misread.
    var shareText: String {
        let latitude = String(format: "%.6f", self.latitude)
        let longitude = String(format: "%.6f", self.longitude)
        return "https://maps.google.com/?q=\(latitude),\(longitude)"
    }

    /// How far this is from a given point, in metres. Used for sorting, not shown.
    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
    }
}

/// How the destinations list is ordered.
enum DestinationOrder: String, CaseIterable, Identifiable, Sendable {
    case mostVisited = "Most visited"
    case recent = "Recent"
    case nearest = "Nearest"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .mostVisited: "arrow.up.arrow.down"
        case .recent: "clock"
        case .nearest: "location"
        }
    }
}

/// Turns visited places into a shortlist worth sending to a car.
///
/// Kept out of the view so the ordering — which is the whole feature — can be
/// tested without a map, a database or a Tesla.
enum DestinationShortlist {
    /// The most a shortlist shows. Ten is what the request asked for and about
    /// what fits on a phone screen without becoming a second history page.
    static let limit = 10

    static func make(
        from places: [VisitedPlace],
        order: DestinationOrder,
        filter: String = "",
        origin: CLLocationCoordinate2D? = nil,
        limit: Int = limit
    ) -> [CarDestination] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = places.filter { place in
            query.isEmpty || place.name.localizedCaseInsensitiveContains(query)
        }
        let destinations = matching.map(CarDestination.init(place:))

        let ordered: [CarDestination]
        switch order {
        case .mostVisited:
            // Ties broken by recency, so two places visited three times each do
            // not swap position every time the list is rebuilt.
            ordered = destinations.sorted {
                $0.visits == $1.visits ? $0.lastVisit > $1.lastVisit : $0.visits > $1.visits
            }
        case .recent:
            ordered = destinations.sorted { $0.lastVisit > $1.lastVisit }
        case .nearest:
            // Without somewhere to measure from, "nearest" has no meaning and
            // silently returning an arbitrary order would be a lie. Fall back to
            // the ordering that is always true.
            guard let origin else {
                return make(from: places, order: .mostVisited, filter: filter, limit: limit)
            }
            ordered = destinations.sorted { $0.distance(from: origin) < $1.distance(from: origin) }
        }
        return Array(ordered.prefix(limit))
    }
}
