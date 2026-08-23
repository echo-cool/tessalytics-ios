import XCTest
@testable import Tessalytics

/// HTTP is opt-in. Local/private addresses are the normal compatibility case,
/// but a public IP and port can be enabled deliberately for older deployments.
final class ServerURLSafetyTests: XCTestCase {
    private func draft(_ url: String, allowsLocalHTTP: Bool = true) -> ProfileDraft {
        var draft = ProfileDraft()
        draft.serverURL = url
        draft.authenticationMethod = .bearer
        draft.token = "secret"
        draft.allowsLocalHTTP = allowsLocalHTTP
        return draft
    }

    private func accepts(_ url: String, allowsLocalHTTP: Bool = true) -> Bool {
        (try? draft(url, allowsLocalHTTP: allowsLocalHTTP).profile()) != nil
    }

    func testHTTPSIsAlwaysAccepted() {
        XCTAssertTrue(accepts("https://tessalytics.example.com", allowsLocalHTTP: false))
    }

    func testCleartextIsRefusedUnlessItIsAskedFor() {
        XCTAssertFalse(accepts("http://192.168.1.10:3022", allowsLocalHTTP: false))
        XCTAssertFalse(accepts("http://203.0.113.10:3022", allowsLocalHTTP: false))
        XCTAssertTrue(accepts("http://203.0.113.10:3022", allowsLocalHTTP: true))
    }

    func testCleartextIsAcceptedForARealPrivateAddress() {
        for host in ["127.0.0.1", "10.0.0.4", "192.168.50.2", "172.16.0.9", "172.20.0.5", "172.31.255.1"] {
            XCTAssertTrue(accepts("http://\(host):3022"), "\(host) is on the local network")
        }
    }

    func testTheDockerDefaultBridgeRangeIsAccepted() {
        // 172.16.0.0/12 is 172.16 through 172.31. Matching the text "172.16."
        // rejected every address Docker actually hands out.
        XCTAssertTrue(accepts("http://172.17.0.2:3022"))
        XCTAssertTrue(accepts("http://172.28.5.1:3022"))
    }

    func testAddressClassificationStillDistinguishesPublicFromPrivate() {
        for host in ["172.15.0.1", "172.32.0.1", "11.0.0.1", "193.168.1.1", "8.8.8.8"] {
            XCTAssertFalse(ProfileDraft.isLocal(host), "\(host) is not on the local network")
        }
    }

    /// The bug: `hasPrefix("10.")` is true of `10.example.com`, which anyone can
    /// register. The app would have accepted it as "local", downgraded to
    /// cleartext, and put the bearer token on the wire for it.
    func testAPublicHostnameThatLooksLikeAPrivateAddressIsNotClassifiedAsLocal() {
        for host in ["10.example.com", "127.0.0.1.example.com", "192.168.evil.test", "172.16.attacker.net"] {
            XCTAssertFalse(ProfileDraft.isLocal(host), "\(host) is a public name, not a private address")
        }
    }

    func testLocalhostAndBonjourNamesAreAccepted() {
        XCTAssertTrue(accepts("http://localhost:3022"))
        XCTAssertTrue(accepts("http://teslamate.local:3022"))
    }

    func testIPv6LoopbackAndUniqueLocalAreAccepted() {
        XCTAssertTrue(ProfileDraft.isLocal("::1"))
        XCTAssertTrue(ProfileDraft.isLocal("[::1]"))
        XCTAssertTrue(ProfileDraft.isLocal("fd00::1"))
        XCTAssertFalse(ProfileDraft.isLocal("2001:4860:4860::8888"), "A public IPv6 address is not local")
    }

    func testAMalformedURLIsRefused() {
        XCTAssertFalse(accepts("not a url", allowsLocalHTTP: false))
        XCTAssertFalse(accepts("ftp://192.168.1.1"))
        XCTAssertFalse(accepts("https://", allowsLocalHTTP: false))
    }

    func testTheAppTransportSecurityPolicyIsActuallyInThePlist() {
        // `INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsArbitraryLoads` produced
        // no key at all: ATS dictionaries cannot be set that way. The policy
        // shipped as nothing for several releases, and the local-HTTP setting
        // could not work on a device.
        let ats = Bundle(for: type(of: self)).infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
            ?? Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
        guard let ats else {
            return XCTFail("The app declares no App Transport Security policy at all.")
        }
        XCTAssertEqual(
            ats["NSAllowsArbitraryLoads"] as? Bool,
            true,
            "ATS must permit the explicit public-HTTP mode; ProfileDraft remains the opt-in guard"
        )
        XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true, "Local HTTP has to be permitted to work")
    }
}
