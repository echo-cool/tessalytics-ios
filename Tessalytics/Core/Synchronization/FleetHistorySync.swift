import Foundation
import SwiftData

/// Pulls the whole drive and charge history so fleet-wide statistics are exact.
///
/// Totals like logged distance, energy added and charge cycles are sums over
/// every session ever recorded — a single page of the newest thirty is not
/// enough. TeslaMateApi has no totals endpoint (`/statistics`, `/totals` and
/// `/consumption` all 404), so the app pages the list endpoints once and keeps
/// the result, then only tops up with the newest page on later launches.
@MainActor
struct FleetHistorySync {
    /// TeslaMateApi caps `show` at 100.
    static let pageSize = 100
    /// A guard against paging forever if a server ignores `page`.
    private static let maximumPages = 60

    let context: ModelContext

    enum Mode: Equatable {
        /// Every page, oldest to newest. Used the first time and after a reset.
        case full
        /// The newest page only, which is enough to pick up anything added since
        /// the last successful sync.
        case incremental
    }

    struct Result: Equatable {
        var drivesSeen = 0
        var chargesSeen = 0
        var completedFullSync = false
    }

    func mode(serverID: UUID, carID: Int) -> Mode {
        record(serverID: serverID, carID: carID)?.lastSuccess == nil ? .full : .incremental
    }

    /// - Parameter onProgress: called on the main actor after each page so a
    ///   first-run sync can show progress rather than appearing to hang.
    func run(
        client: any VehicleDataAPI,
        serverID: UUID,
        carID: Int,
        mode: Mode,
        onProgress: ((Result) -> Void)? = nil
    ) async throws -> Result {
        var result = Result()

        // The two legs are attempted independently. A drive page that fails must
        // not cost the charge history as well: reporting "no charges" because an
        // unrelated request failed is worse than reporting a partial sync.
        var failure: Error?

        do {
            result.drivesSeen = try await page(mode: mode) { page in
                let response = try await client.drives(carID: carID, page: page, show: Self.pageSize, filter: .init())
                try persist(drives: response.drives, serverID: serverID, carID: carID)
                result.drivesSeen += response.drives.count
                onProgress?(result)
                return response.drives.count
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = error
        }

        do {
            result.chargesSeen = try await page(mode: mode) { page in
                let response = try await client.charges(carID: carID, page: page, show: Self.pageSize, filter: .init())
                try persist(charges: response.charges, serverID: serverID, carID: carID)
                result.chargesSeen += response.charges.count
                onProgress?(result)
                return response.charges.count
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = failure ?? error
        }

        // Only a clean full pass may be marked synced. Marking a partial one would
        // switch later runs to incremental and leave the gap unfilled for good.
        if let failure { throw failure }
        if mode == .full {
            result.completedFullSync = true
            markSynced(serverID: serverID, carID: carID)
        }
        return result
    }

    /// Walks pages until one comes back short, which is the only end-of-list
    /// signal the API gives — the response carries no total count.
    private func page(mode: Mode, body: (Int) async throws -> Int) async throws -> Int {
        var total = 0
        var page = 1
        while page <= Self.maximumPages {
            let count = try await body(page)
            total += count
            if mode == .incremental || count < Self.pageSize { break }
            page += 1
        }
        return total
    }

    private func persist(drives: [DriveSummaryDTO], serverID: UUID, carID: Int) throws {
        for dto in drives {
            let key = DriveRecord.key(serverID: serverID, carID: carID, id: dto.driveId)
            let descriptor = FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.cacheKey == key })
            if let existing = try context.fetch(descriptor).first {
                existing.startDate = dto.startDate?.value
                existing.endDate = dto.endDate?.value
                existing.startAddress = dto.startAddress
                existing.endAddress = dto.endAddress
                existing.distance = dto.odometerDetails?.odometerDistance
                existing.durationMinutes = dto.durationMin
                existing.speedMax = dto.speedMax
                existing.speedAverage = dto.speedAvg
                existing.energy = dto.energyConsumedNet
                existing.efficiency = dto.consumptionNet
                existing.updatedAt = .now
                existing.apply(dto)
            } else {
                context.insert(DriveRecord(serverID: serverID, carID: carID, dto: dto))
            }
        }
        try context.save()
    }

    private func persist(charges: [ChargeSummaryDTO], serverID: UUID, carID: Int) throws {
        for dto in charges {
            let key = ChargeRecord.key(serverID: serverID, carID: carID, id: dto.chargeId)
            let descriptor = FetchDescriptor<ChargeRecord>(predicate: #Predicate { $0.cacheKey == key })
            if let existing = try context.fetch(descriptor).first {
                existing.startDate = dto.startDate?.value
                existing.endDate = dto.endDate?.value
                existing.address = dto.address
                existing.energyAdded = dto.chargeEnergyAdded
                existing.energyUsed = dto.chargeEnergyUsed
                existing.cost = dto.cost
                existing.durationMinutes = dto.durationMin
                existing.updatedAt = .now
                existing.apply(dto)
            } else {
                context.insert(ChargeRecord(serverID: serverID, carID: carID, dto: dto))
            }
        }
        try context.save()
    }

    // MARK: - Sync bookkeeping

    static func metadataKey(serverID: UUID, carID: Int) -> String {
        "\(serverID.uuidString):\(carID):fleet-history"
    }

    private func key(serverID: UUID, carID: Int) -> String {
        Self.metadataKey(serverID: serverID, carID: carID)
    }

    private func record(serverID: UUID, carID: Int) -> SyncMetadataRecord? {
        let wanted = key(serverID: serverID, carID: carID)
        let descriptor = FetchDescriptor<SyncMetadataRecord>(predicate: #Predicate { $0.cacheKey == wanted })
        return try? context.fetch(descriptor).first
    }

    private func markSynced(serverID: UUID, carID: Int) {
        if let existing = record(serverID: serverID, carID: carID) {
            existing.lastSuccess = .now
        } else {
            context.insert(SyncMetadataRecord(key: key(serverID: serverID, carID: carID), lastSuccess: .now))
        }
        try? context.save()
    }

    /// Age of the last completed full sync, for the "data as of" line.
    func lastFullSync(serverID: UUID, carID: Int) -> Date? {
        record(serverID: serverID, carID: carID)?.lastSuccess
    }
}
