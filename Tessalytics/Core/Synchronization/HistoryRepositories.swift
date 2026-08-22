import Foundation
import SwiftData

@MainActor
protocol DriveRepositoryProtocol {
    func cached(serverID: UUID, carID: Int) -> [DriveRecord]
    func refresh(client: any VehicleDataAPI, serverID: UUID, carID: Int, page: Int, filter: DateRangeFilter) async throws -> [DriveRecord]
    func detail(client: any VehicleDataAPI, serverID: UUID, carID: Int, driveID: Int) async throws -> DriveDetailDTO
}

@MainActor
final class DriveRepository: DriveRepositoryProtocol {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func cached(serverID: UUID, carID: Int) -> [DriveRecord] {
        let server = serverID.uuidString
        var descriptor = FetchDescriptor<DriveRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == carID },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return (try? context.fetch(descriptor)) ?? []
    }

    func refresh(client: any VehicleDataAPI, serverID: UUID, carID: Int, page: Int, filter: DateRangeFilter) async throws -> [DriveRecord] {
        let response = try await client.drives(carID: carID, page: page, show: 30, filter: filter)
        for dto in response.drives {
            let key = DriveRecord.key(serverID: serverID, carID: carID, id: dto.driveId)
            let descriptor = FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.cacheKey == key })
            if let existing = try context.fetch(descriptor).first {
                existing.startDate = dto.startDate?.value; existing.endDate = dto.endDate?.value
                existing.startAddress = dto.startAddress; existing.endAddress = dto.endAddress
                existing.distance = dto.odometerDetails?.odometerDistance; existing.durationMinutes = dto.durationMin
                existing.speedMax = dto.speedMax; existing.speedAverage = dto.speedAvg
                existing.energy = dto.energyConsumedNet; existing.efficiency = dto.consumptionNet; existing.updatedAt = .now
                existing.apply(dto)
            } else { context.insert(DriveRecord(serverID: serverID, carID: carID, dto: dto)) }
        }
        try context.save()
        return cached(serverID: serverID, carID: carID)
    }

    /// The stored payload for a drive, still encoded.
    ///
    /// For the history rows, which want a route and not a decoded drive: decoding
    /// twenty thousand samples belongs off the main actor, and this hands over the
    /// bytes so it can happen there.
    func cachedDetailPayload(serverID: UUID, carID: Int, driveID: Int) -> Data? {
        let key = DriveRecord.key(serverID: serverID, carID: carID, id: driveID)
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        return (try? context.fetch(descriptor).first)?.payload
    }

    func detail(client: any VehicleDataAPI, serverID: UUID, carID: Int, driveID: Int) async throws -> DriveDetailDTO {
        let key = DriveRecord.key(serverID: serverID, carID: carID, id: driveID)
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        if let cache = try context.fetch(descriptor).first,
           let decoded = try? JSONDecoder.tessalytics.decode(DriveDetailDTO.self, from: cache.payload) { return decoded }
        let detail = try await client.drive(carID: carID, driveID: driveID).drive
        if detail.endDate?.value != nil {
            let payload = try JSONEncoder().encode(detail)
            context.insert(DetailCacheRecord(key: key, serverID: serverID, carID: carID, kind: "drive", backendID: driveID, payload: payload, completed: true))
            try context.save()
        }
        return detail
    }
}

@MainActor
protocol ChargeRepositoryProtocol {
    func cached(serverID: UUID, carID: Int) -> [ChargeRecord]
    func refresh(client: any VehicleDataAPI, serverID: UUID, carID: Int, page: Int, filter: DateRangeFilter) async throws -> [ChargeRecord]
    func detail(client: any VehicleDataAPI, serverID: UUID, carID: Int, chargeID: Int) async throws -> ChargeDetailDTO
}

@MainActor
final class ChargeRepository: ChargeRepositoryProtocol {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func cached(serverID: UUID, carID: Int) -> [ChargeRecord] {
        let server = serverID.uuidString
        var descriptor = FetchDescriptor<ChargeRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == carID },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return (try? context.fetch(descriptor)) ?? []
    }

    func refresh(client: any VehicleDataAPI, serverID: UUID, carID: Int, page: Int, filter: DateRangeFilter) async throws -> [ChargeRecord] {
        let response = try await client.charges(carID: carID, page: page, show: 30, filter: filter)
        for dto in response.charges {
            let key = ChargeRecord.key(serverID: serverID, carID: carID, id: dto.chargeId)
            let descriptor = FetchDescriptor<ChargeRecord>(predicate: #Predicate { $0.cacheKey == key })
            if let existing = try context.fetch(descriptor).first {
                existing.startDate = dto.startDate?.value; existing.endDate = dto.endDate?.value; existing.address = dto.address
                existing.energyAdded = dto.chargeEnergyAdded; existing.energyUsed = dto.chargeEnergyUsed
                existing.cost = dto.cost; existing.durationMinutes = dto.durationMin; existing.updatedAt = .now
                existing.apply(dto)
            } else { context.insert(ChargeRecord(serverID: serverID, carID: carID, dto: dto)) }
        }
        try context.save()
        return cached(serverID: serverID, carID: carID)
    }

    func detail(client: any VehicleDataAPI, serverID: UUID, carID: Int, chargeID: Int) async throws -> ChargeDetailDTO {
        let key = ChargeRecord.key(serverID: serverID, carID: carID, id: chargeID)
        let descriptor = FetchDescriptor<DetailCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        if let cache = try context.fetch(descriptor).first,
           let decoded = try? JSONDecoder.tessalytics.decode(ChargeDetailDTO.self, from: cache.payload) { return decoded }
        let detail = try await client.charge(carID: carID, chargeID: chargeID).charge
        if detail.endDate?.value != nil {
            context.insert(DetailCacheRecord(key: key, serverID: serverID, carID: carID, kind: "charge", backendID: chargeID,
                                             payload: try JSONEncoder().encode(detail), completed: true))
            try context.save()
        }
        return detail
    }
}

extension JSONDecoder {
    static var tessalytics: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder }
}
