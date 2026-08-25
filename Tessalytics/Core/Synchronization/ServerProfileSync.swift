import Foundation

/// Carries the owner's server list between their own devices.
///
/// Not CloudKit, and not the SwiftData store. Mirroring the store would mean
/// dropping the nine `@Attribute(.unique)` cache keys the history dedupe is built
/// on — CloudKit supports no uniqueness constraint — and it would push a year of
/// cached drives through an account database to re-derive something the owner's
/// own server can hand back in a minute. What actually needs to travel is four
/// flat fields per server, which is what `NSUbiquitousKeyValueStore` is for: no
/// schema, no migration, no container, and a hard 1 MB ceiling that this cannot
/// approach.
///
/// Credentials are deliberately absent. They travel through iCloud Keychain,
/// which is end-to-end encrypted; a bearer token in key-value storage would not
/// be.
struct SyncedServerProfile: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var baseURLString: String
    var authenticationMethodRaw: String
    var allowsLocalHTTP: Bool
    /// When this device last wrote the record, used to settle a disagreement
    /// between two devices that edited the same server while apart.
    var updatedAt: Date

    init?(profile: ServerProfile, updatedAt: Date = .now) {
        guard !profile.name.isEmpty else { return nil }
        id = profile.id
        name = profile.name
        baseURLString = profile.baseURL.absoluteString
        authenticationMethodRaw = profile.authenticationMethod.rawValue
        allowsLocalHTTP = profile.allowsLocalHTTP
        self.updatedAt = updatedAt
    }

    var profile: ServerProfile? {
        guard let url = URL(string: baseURLString),
              let method = AuthenticationMethod(rawValue: authenticationMethodRaw) else { return nil }
        return ServerProfile(
            id: id, name: name, baseURL: url, authenticationMethod: method,
            allowsLocalHTTP: allowsLocalHTTP, isSelected: false
        )
    }
}

/// The key-value store, behind a protocol so the merge can be tested without one.
protocol UbiquitousStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousStore {
    func set(_ data: Data?, forKey key: String) {
        if let data { set(data, forKey: key) as Void } else { removeObject(forKey: key) }
    }
}

/// Reads and writes the shared server list, and merges it with what is here.
struct ServerProfileSync: Sendable {
    static let key = "servers.v1"

    /// Merges the list this device holds with the one the account holds.
    ///
    /// Last writer wins per server, by `updatedAt`. A clock that disagrees
    /// between devices can therefore pick the wrong one — which is why this is
    /// used for a name and an address, and never for anything whose loss would
    /// matter. Nothing is deleted by merging: a server missing from one side is
    /// treated as not-yet-known there rather than as removed, because the two are
    /// indistinguishable here and resurrecting a deleted row is a smaller harm
    /// than silently dropping a server the owner still uses.
    static func merge(
        local: [SyncedServerProfile],
        remote: [SyncedServerProfile]
    ) -> [SyncedServerProfile] {
        var byID: [UUID: SyncedServerProfile] = [:]
        for profile in local { byID[profile.id] = profile }
        for profile in remote {
            guard let existing = byID[profile.id] else {
                byID[profile.id] = profile
                continue
            }
            if profile.updatedAt > existing.updatedAt { byID[profile.id] = profile }
        }
        return byID.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    static func read(from store: any UbiquitousStore) -> [SyncedServerProfile] {
        guard let data = store.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SyncedServerProfile].self, from: data)) ?? []
    }

    static func write(_ profiles: [SyncedServerProfile], to store: any UbiquitousStore) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        store.set(data, forKey: key)
        store.synchronize()
    }

    /// Removes a server from the shared list, for a deletion the owner asked for
    /// rather than one inferred from absence.
    static func remove(id: UUID, from store: any UbiquitousStore) {
        let remaining = read(from: store).filter { $0.id != id }
        write(remaining, to: store)
    }
}
