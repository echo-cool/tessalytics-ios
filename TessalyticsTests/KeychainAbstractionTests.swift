import XCTest
@testable import Tessalytics

final class KeychainAbstractionTests: XCTestCase {
    func testCredentialStoreCanBeReplacedByMemoryImplementation() throws {
        let store = MemoryCredentialStore(); let id = UUID(); let credentials = StoredCredentials(method: .bearer, username: nil, secret: "private")
        try store.save(credentials, profileID: id); XCTAssertEqual(try store.credentials(profileID: id), credentials)
        try store.delete(profileID: id); XCTAssertNil(try store.credentials(profileID: id))
    }

    func testOwnerCredentialsRetainRotatingTokenPair() throws {
        let store = MemoryOwnerStore()
        let credentials = OwnerAPICredentials(accessToken: "access", refreshToken: "refresh", expiresAt: .now, region: .global)
        try store.save(credentials)
        XCTAssertEqual(try store.credentials(), credentials)
        try store.delete()
        XCTAssertNil(try store.credentials())
    }
}
private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [UUID: StoredCredentials] = [:]
    func save(_ credentials: StoredCredentials, profileID: UUID) throws { values[profileID] = credentials }
    func credentials(profileID: UUID) throws -> StoredCredentials? { values[profileID] }
    func delete(profileID: UUID) throws { values.removeValue(forKey: profileID) }
}

private final class MemoryOwnerStore: OwnerCredentialStore, @unchecked Sendable {
    var value: OwnerAPICredentials?
    func save(_ credentials: OwnerAPICredentials) throws { value = credentials }
    func credentials() throws -> OwnerAPICredentials? { value }
    func delete() throws { value = nil }
}
