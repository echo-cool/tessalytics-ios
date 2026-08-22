import Foundation
import SwiftData

/// The small drawings the history rows carry: a drive's route and a charge's
/// curve.
///
/// Both used to be derived inside the row itself, on the main actor, from the
/// full detail payload — up to twenty thousand samples decoded and then reduced
/// by Douglas-Peucker, per row, while the list was being dragged. Worse, a row
/// scrolled out and back recomputed all of it, because a recycled row runs its
/// task again.
///
/// So: computed once, off the main actor, and kept here by id. A row that returns
/// to the screen costs a dictionary lookup.
@MainActor
final class HistoryPreviews {
    static let shared = HistoryPreviews()

    /// Enough for a long scroll without holding a session's worth of coordinates
    /// for a list nobody is looking at any more.
    private static let limit = 200

    private var routes: [Int: [CoordinateDTO]] = [:]
    private var routeOrder: [Int] = []
    private var curves: [Int: [ChargeCurvePoint]] = [:]
    private var curveOrder: [Int] = []

    private init() {}

    func route(driveID: Int) -> [CoordinateDTO]? { routes[driveID] }

    func store(route: [CoordinateDTO], driveID: Int) {
        if routes.updateValue(route, forKey: driveID) == nil { routeOrder.append(driveID) }
        while routeOrder.count > Self.limit {
            routes.removeValue(forKey: routeOrder.removeFirst())
        }
    }

    func curve(chargeID: Int) -> [ChargeCurvePoint]? { curves[chargeID] }

    func store(curve: [ChargeCurvePoint], chargeID: Int) {
        if curves.updateValue(curve, forKey: chargeID) == nil { curveOrder.append(chargeID) }
        while curveOrder.count > Self.limit {
            curves.removeValue(forKey: curveOrder.removeFirst())
        }
    }

    /// Dropped when the vehicle changes: the ids belong to that vehicle's history.
    func removeAll() {
        routes.removeAll()
        routeOrder.removeAll()
        curves.removeAll()
        curveOrder.removeAll()
    }

    /// A drive's route from an undecoded payload, decoded and reduced away from
    /// the main actor.
    nonisolated static func route(from payload: Data) async -> [CoordinateDTO] {
        await Task.detached(priority: .utility) {
            guard let detail = try? JSONDecoder.tessalytics.decode(DriveDetailDTO.self, from: payload) else { return [] }
            return RouteSimplifier.simplify(detail.driveDetails.map(\.coordinate), tolerance: 0.00025)
        }.value
    }

    nonisolated static func route(from coordinates: [CoordinateDTO]) async -> [CoordinateDTO] {
        await Task.detached(priority: .utility) {
            RouteSimplifier.simplify(coordinates, tolerance: 0.00025)
        }.value
    }
}
