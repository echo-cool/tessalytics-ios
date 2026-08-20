import Foundation
import SwiftData

struct CachedVehicleStatus: Sendable {
    let status: VehicleStatus
    let units: UnitsDTO?
    let fetchedAt: Date
}

@MainActor
final class VehicleStatusCache {
    private struct Payload: Codable {
        let status: VehicleStatus
        let units: UnitsDTO?
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The last status recorded while the car was awake.
    ///
    /// A sleeping car reports nothing about its doors, locks or cabin, and the
    /// app used to answer "unknown" — truthful but useless, since the last known
    /// state is exactly what an owner wants when they cannot ask the car. Kept
    /// apart from the general cache because that one holds whatever arrived last,
    /// asleep or not.
    func loadLastLive(serverID: UUID, carID: Int) -> CachedVehicleStatus? {
        read(key: Self.liveKey(serverID: serverID, carID: carID))
    }

    func load(serverID: UUID, carID: Int) -> CachedVehicleStatus? {
        read(key: Self.key(serverID: serverID, carID: carID))
    }

    private func read(key: String) -> CachedVehicleStatus? {
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        guard let record = try? context.fetch(descriptor).first,
              let payload = try? JSONDecoder.tessalytics.decode(Payload.self, from: record.payload) else {
            return nil
        }
        return CachedVehicleStatus(status: payload.status, units: payload.units, fetchedAt: record.cachedAt)
    }

    func save(status: VehicleStatus, units: UnitsDTO?, serverID: UUID, carID: Int, fetchedAt: Date = .now) {
        write(status: status, units: units, serverID: serverID, carID: carID, fetchedAt: fetchedAt,
              key: Self.key(serverID: serverID, carID: carID))
        // Only a live reading may overwrite the last-known one, or a night of
        // asleep polls would erase it.
        if status.reportsLiveTelemetry {
            write(status: status, units: units, serverID: serverID, carID: carID, fetchedAt: fetchedAt,
                  key: Self.liveKey(serverID: serverID, carID: carID))
        }
    }

    private func write(
        status: VehicleStatus,
        units: UnitsDTO?,
        serverID: UUID,
        carID: Int,
        fetchedAt: Date,
        key: String
    ) {
        guard let payload = try? JSONEncoder().encode(Payload(status: status, units: units)) else { return }
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })

        if let record = try? context.fetch(descriptor).first {
            record.payload = payload
            record.cachedAt = fetchedAt
            record.completed = true
        } else {
            let record = DetailCacheRecord(
                key: key,
                serverID: serverID,
                carID: carID,
                kind: "status",
                backendID: carID,
                payload: payload,
                completed: true
            )
            record.cachedAt = fetchedAt
            context.insert(record)
        }
        try? context.save()
    }

    private static func key(serverID: UUID, carID: Int) -> String {
        "\(serverID.uuidString):\(carID):status"
    }

    private static func liveKey(serverID: UUID, carID: Int) -> String {
        "\(serverID.uuidString):\(carID):status-live"
    }
}
