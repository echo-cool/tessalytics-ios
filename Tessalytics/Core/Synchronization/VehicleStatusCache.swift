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

    func load(serverID: UUID, carID: Int) -> CachedVehicleStatus? {
        let key = Self.key(serverID: serverID, carID: carID)
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        guard let record = try? context.fetch(descriptor).first,
              let payload = try? JSONDecoder.tessalytics.decode(Payload.self, from: record.payload) else {
            return nil
        }
        return CachedVehicleStatus(status: payload.status, units: payload.units, fetchedAt: record.cachedAt)
    }

    func save(status: VehicleStatus, units: UnitsDTO?, serverID: UUID, carID: Int, fetchedAt: Date = .now) {
        let key = Self.key(serverID: serverID, carID: carID)
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
}
