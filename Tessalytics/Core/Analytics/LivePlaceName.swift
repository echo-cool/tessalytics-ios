import CoreLocation
import Foundation

/// How much of an address is worth saying.
enum PlacePrecision: Equatable, Sendable {
    /// The road, and the town it is in. What a moving car is on.
    case street
    /// The full street address. What a stopped car is at.
    case address
}

/// Turns a coordinate into something a person would say out loud.
///
/// A protocol so the app can be driven without a network: demo mode and the UI
/// tests supply their own, and neither the tests nor a car in a tunnel depend on
/// Apple's geocoder answering.
protocol PlaceNaming: Sendable {
    func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String?
}

/// Apple's reverse geocoder.
struct GeocodedPlaceNames: PlaceNaming {
    func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return Self.describe(placemark, precision: precision)
    }

    /// The parts of a placemark worth showing, in the order they read.
    ///
    /// A house number is exactly what a parked car wants and exactly what a
    /// moving one does not: "2479 Crystal Dr" is where the car is for the tenth
    /// of a second it takes to pass the building. Moving, the road is the answer.
    static func describe(_ placemark: CLPlacemark, precision: PlacePrecision) -> String? {
        let town = placemark.locality?.nilIfEmpty ?? placemark.subAdministrativeArea?.nilIfEmpty
        let road = placemark.thoroughfare?.nilIfEmpty
        let area = placemark.subLocality?.nilIfEmpty

        switch precision {
        case .street:
            let place = road ?? area ?? placemark.name?.nilIfEmpty
            return Self.joined(place, town)
        case .address:
            // `name` carries the house number when there is one, and falls back
            // to the road on its own when there is not.
            let place = placemark.name?.nilIfEmpty ?? Self.joined(road, area)
            return Self.joined(place, town)
        }
    }

    /// Joins two parts, dropping either if it is missing and refusing to repeat
    /// one that the other already contains ("Mountain View, Mountain View").
    private static func joined(_ first: String?, _ second: String?) -> String? {
        guard let first else { return second }
        guard let second, !first.localizedCaseInsensitiveContains(second) else { return first }
        return "\(first), \(second)"
    }
}

/// A fixed answer, for demo mode and for tests.
struct FixedPlaceNames: PlaceNaming {
    let street: String
    let address: String

    func name(for coordinate: CoordinateDTO, precision: PlacePrecision) async -> String? {
        precision == .street ? street : address
    }
}

/// Where the car is, in words, kept current as it moves.
///
/// Reverse geocoding is a network call with a published rate limit, and a driving
/// car reports a new position two or three times a second — so the interesting
/// part of this type is everything that stops it asking. A lookup happens when
/// the car has travelled far enough for the answer to have changed, and never
/// while one is already in flight.
@MainActor
@Observable
final class LivePlaceName {
    /// How far the car must travel before the road name could have changed, in
    /// metres. A little over a city block.
    static let minimumMovement: CLLocationDistance = 150
    /// The floor between lookups, whatever the distance. `CLGeocoder` is
    /// rate-limited per app, and a motorway at speed would otherwise ask every
    /// five seconds for a road whose name has not changed in twenty miles.
    static let minimumInterval: TimeInterval = 12

    /// The name to show, or nil when nowhere has been resolved yet.
    private(set) var name: String?
    /// What `name` describes, so a stale name is never shown beside a new place.
    private(set) var resolvedAt: CoordinateDTO?

    private let resolver: any PlaceNaming
    private var lookup: Task<Void, Never>?
    private var lastRequestedAt: Date?
    private var lastPrecision: PlacePrecision?

    init(resolver: any PlaceNaming = GeocodedPlaceNames()) {
        self.resolver = resolver
    }

    /// Asks for a name for this position, if this position needs one.
    func update(for coordinate: CoordinateDTO?, precision: PlacePrecision, now: Date = .now) {
        guard let coordinate else {
            clear()
            return
        }
        guard shouldLookUp(coordinate, precision: precision, now: now) else { return }
        lastRequestedAt = now
        lastPrecision = precision
        lookup?.cancel()
        lookup = Task { [resolver] in
            let resolved = await resolver.name(for: coordinate, precision: precision)
            guard !Task.isCancelled else { return }
            // A failed lookup leaves the previous name in place: a car in a
            // tunnel is still on the road it was on.
            if let resolved {
                name = resolved
                resolvedAt = coordinate
            }
            lookup = nil
        }
    }

    func clear() {
        lookup?.cancel()
        lookup = nil
        name = nil
        resolvedAt = nil
        lastRequestedAt = nil
        lastPrecision = nil
    }

    /// Whether this position is far enough, or old enough, to be worth asking
    /// about. Exposed for the tests, which is where the arithmetic is checked.
    func shouldLookUp(_ coordinate: CoordinateDTO, precision: PlacePrecision, now: Date) -> Bool {
        guard lookup == nil else { return false }
        // Coming to a stop is worth a second look: the road the car was on
        // becomes the address it is standing at.
        if precision != lastPrecision { return true }
        guard let resolvedAt, name != nil else { return true }
        guard let lastRequestedAt else { return true }
        guard now.timeIntervalSince(lastRequestedAt) >= Self.minimumInterval else { return false }
        return Self.distance(from: resolvedAt, to: coordinate) >= Self.minimumMovement
    }

    /// Metres between two coordinates. Nonisolated: it is arithmetic, and both
    /// the throttle and the tests want it without an actor hop.
    nonisolated static func distance(from one: CoordinateDTO, to other: CoordinateDTO) -> CLLocationDistance {
        CLLocation(latitude: one.latitude, longitude: one.longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
