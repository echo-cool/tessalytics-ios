import XCTest
@testable import Tessalytics

/// Tests for signing a browser in to the web dashboard.
///
/// The scanned payload is the interesting part: it is a string that came from a
/// camera pointed at whatever was in front of it, and everything downstream —
/// which server, which pairing, what gets approved — is derived from it. So most
/// of what follows is about refusing things that are not a pairing code.
final class WebPairingTests: XCTestCase {
    private let baseURL = URL(string: "https://backend.invalid")!

    private func client(_ responses: [String: String], statusCode: Int = 200) -> (TessalyticsBackendClient, PairingStubTransport) {
        let transport = PairingStubTransport(responses: responses, statusCode: statusCode)
        return (
            TessalyticsBackendClient(baseURL: baseURL, authentication: .bearer("token"), transport: transport),
            transport
        )
    }

    // MARK: - Parsing what was scanned

    func testAValidPayloadParses() throws {
        let scanned = try XCTUnwrap(
            WebPairingCode(
                scanned: "tessalytics://pair?v=1&id=200230a519038f0cc1cbbdb54321fe8e&code=YJBS-MRCB&origin=https%3A%2F%2Fcar.example.com%3A3022"
            )
        )
        XCTAssertEqual(scanned.pairingID, "200230a519038f0cc1cbbdb54321fe8e")
        XCTAssertEqual(scanned.code, "YJBS-MRCB")
        XCTAssertEqual(scanned.origin, "https://car.example.com:3022")
    }

    func testAPayloadWithoutAnOriginStillParses() throws {
        // The origin is shown to the person approving, not required to approve.
        let scanned = try XCTUnwrap(WebPairingCode(scanned: "tessalytics://pair?v=1&id=abcdef1234567890&code=ABCD-EFGH"))
        XCTAssertNil(scanned.origin)
        XCTAssertEqual(scanned.code, "ABCD-EFGH")
    }

    func testACodeIsNormalisedRatherThanRejected() throws {
        // Case and the hyphen carry no information, and the server normalises the
        // same way. A code that round-trips through a hand-typed field must match.
        let scanned = try XCTUnwrap(WebPairingCode(scanned: "tessalytics://pair?id=abcdef1234567890&code=yjbsmrcb"))
        XCTAssertEqual(scanned.code, "YJBS-MRCB")
    }

    func testTheThreeSlashFormParses() throws {
        let scanned = try XCTUnwrap(WebPairingCode(scanned: "tessalytics:///pair?id=abcdef1234567890&code=ABCD-EFGH"))
        XCTAssertEqual(scanned.pairingID, "abcdef1234567890")
    }

    func testSurroundingWhitespaceIsTolerated() {
        XCTAssertNotNil(WebPairingCode(scanned: "  tessalytics://pair?id=abcdef1234567890&code=ABCD-EFGH\n"))
    }

    func testEverythingThatIsNotAPairingCodeIsRefused() {
        // A camera pointed at a car's screen also sees whatever else is in the
        // frame: a parcel's barcode, a URL on a poster, a Wi-Fi QR code.
        let rejected = [
            "https://example.com/pair?id=abcdef1234567890&code=ABCD-EFGH",   // right shape, wrong scheme
            "tessalytics://other?id=abcdef1234567890&code=ABCD-EFGH",        // wrong action
            "tessalytics://pair?id=not-hexadecimal&code=ABCD-EFGH",          // identifier is not one
            "tessalytics://pair?id=abcdef1234567890",                        // no code
            "tessalytics://pair?code=ABCD-EFGH",                            // no identifier
            "tessalytics://pair?id=abcdef1234567890&code=ABC-EFGH",          // code too short
            "tessalytics://pair?id=abc&code=ABCD-EFGH",                      // identifier too short
            "WIFI:S=Tesla;T=WPA;P=hunter2;;",
            "",
            "tessalytics://pair"
        ]
        for payload in rejected {
            XCTAssertNil(WebPairingCode(scanned: payload), "should have refused: \(payload)")
        }
    }

    func testACodeMustHaveExactlyEightUsableCharacters() {
        XCTAssertEqual(WebPairingCode.normalisedCode("abcd-efgh"), "ABCD-EFGH")
        XCTAssertEqual(WebPairingCode.normalisedCode("ABCDEFGH"), "ABCD-EFGH")
        XCTAssertNil(WebPairingCode.normalisedCode("ABCD-EFG"))
        XCTAssertNil(WebPairingCode.normalisedCode("ABCD-EFGHJ"))
        // I, L, O, 0 and 1 are not in the alphabet: they are the characters a
        // person misreads off a screen, so the server never emits them. A string
        // made only of those normalises to nothing rather than to a code.
        XCTAssertNil(WebPairingCode.normalisedCode("ILOO-1111"))
        // And a stray one among eight good characters is dropped rather than
        // failing the code — the same leniency the server's own normaliser
        // applies, which is what keeps the two ends agreeing.
        XCTAssertEqual(WebPairingCode.normalisedCode("ABCDI-EFGH"), "ABCD-EFGH")
    }

    // MARK: - Reading a pairing before approving it

    func testAPairingRequestDecodes() async throws {
        let body = """
        {"data":{"pairing":{"id":"200230a5","code":"YJBS-MRCB","status":"pending",
        "created_at":"2026-08-22T21:16:56.503506+00:00","expires_at":"2026-08-22T21:19:56.503508+00:00",
        "expires_in_seconds":156,
        "client":{"address":"192.168.1.44","user_agent":"Mozilla/5.0 (X11; Tesla) Chrome/79","origin":"http://192.168.1.2:3022","label":"Tesla browser"}}},
        "meta":{"source":"live"}}
        """
        let (api, _) = client(["/v1/auth/pairing/200230a5": body])
        let request = try await api.pairingRequest(id: "200230a5")

        XCTAssertEqual(request.code, "YJBS-MRCB")
        XCTAssertTrue(request.isPending)
        XCTAssertEqual(request.address, "192.168.1.44")
        XCTAssertEqual(request.expiresInSeconds, 156)
        // The confirmation sheet has to name the browser, and a user-agent string
        // is not something anyone reads at a glance.
        XCTAssertEqual(request.browser, "Tesla browser")
    }

    func testAnUnknownBrowserIsNamedRatherThanBlank() {
        let request = WebPairingRequest(
            pairingID: "a", code: "ABCD-EFGH", status: "pending", expiresInSeconds: 100,
            address: nil, userAgent: "SomeUnknownAgent/1", origin: nil, label: "Kitchen laptop"
        )
        XCTAssertEqual(request.browser, "Kitchen laptop")
    }

    func testACodeCanBeLookedUpWhenThereIsNoCamera() async throws {
        let body = """
        {"data":{"pairing":{"id":"aa11","code":"YJBS-MRCB","status":"pending","expires_in_seconds":90,
        "client":{"address":null,"user_agent":null,"origin":null,"label":null}}},"meta":{}}
        """
        let (api, transport) = client(["/v1/auth/pairing/lookup": body])
        let request = try await api.findPairing(code: "YJBS-MRCB")

        XCTAssertEqual(request.pairingID, "aa11")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.decodedBody()?["code"] as? String, "YJBS-MRCB")
    }

    // MARK: - Approving

    func testApprovalSendsTheCodeAndReturnsTheSession() async throws {
        let body = """
        {"data":{"pairing":{"id":"aa11","code":"YJBS-MRCB","status":"approved","expires_in_seconds":120,"client":{}},
        "session":{"id":"bc0929bd","label":"Tesla browser","scope":"read",
        "created_at":"2026-08-22T21:17:20.661899+00:00","expires_at":"2026-09-21T21:17:20.661901+00:00",
        "last_seen_at":"2026-08-22T21:17:20.661901+00:00","client":{"address":"192.168.1.44"}}},"meta":{}}
        """
        let (api, transport) = client(["/v1/auth/pairing/aa11/approve": body])
        let session = try await api.approvePairing(id: "aa11", code: "YJBS-MRCB", label: "Tesla browser")

        XCTAssertEqual(session.id, "bc0929bd")
        XCTAssertEqual(session.label, "Tesla browser")
        // Read-only is the whole point; a session that came back with anything
        // else would be a server this app should not be handing browsers to.
        XCTAssertEqual(session.scope, "read")
        XCTAssertNotNil(session.expiresAt)
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.decodedBody()?["code"] as? String, "YJBS-MRCB")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testAnAlreadyResolvedPairingSurfacesTheServersOwnExplanation() async {
        // 409 is the answer to approving twice, or approving something expired.
        // The server writes a sentence for a person; showing our own instead of
        // theirs is how "reload the page for a new code" gets lost.
        let (api, _) = client(
            ["/v1/auth/pairing/aa11/approve": #"{"detail":"That pairing code has expired. Reload the page for a new one."}"#],
            statusCode: 409
        )
        do {
            _ = try await api.approvePairing(id: "aa11", code: "YJBS-MRCB", label: nil)
            XCTFail("a 409 must not read as success")
        } catch let error as ClientError {
            XCTAssertEqual(error, .serverMessage("That pairing code has expired. Reload the page for a new one."))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAFailedApprovalIsNotRetried() async {
        // Retrying a POST that did reach the server turns a granted approval into
        // a reported failure — the one outcome worse than either.
        let (api, transport) = client([:], statusCode: 503)
        _ = try? await api.approvePairing(id: "aa11", code: "YJBS-MRCB", label: nil)
        XCTAssertEqual(transport.attempts, 1)
    }

    func testAReadStillRetries() async {
        // The generalised transport must not have cost GETs their retry.
        let (api, transport) = client([:], statusCode: 503)
        _ = try? await api.pairingRequest(id: "aa11")
        XCTAssertEqual(transport.attempts, 3)
    }

    func testDenyingUsesTheDenyRoute() async throws {
        let (api, transport) = client(["/v1/auth/pairing/aa11/deny": #"{"data":{"pairing":{"id":"aa11","code":"ABCD-EFGH","status":"denied"}},"meta":{}}"#])
        try await api.denyPairing(id: "aa11")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/v1/auth/pairing/aa11/deny")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
    }

    // MARK: - Taking access away

    func testSessionsDecodeForTheSettingsList() async throws {
        let body = """
        {"data":{"sessions":[
        {"id":"one","label":"Tesla browser","scope":"read","created_at":"2026-08-22T21:17:20.661899+00:00",
         "expires_at":"2026-09-21T21:17:20.661901+00:00","last_seen_at":"2026-08-22T21:40:00.000001+00:00",
         "client":{"address":"192.168.1.44"}},
        {"id":"two","label":null,"scope":null,"created_at":null,"expires_at":null,"last_seen_at":null,"client":null}]},
        "meta":{}}
        """
        let (api, _) = client(["/v1/auth/sessions": body])
        let sessions = try await api.webSessions()

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].address, "192.168.1.44")
        XCTAssertNotNil(sessions[0].lastSeenAt)
        // A server that answers sparsely must still list; the row shows what it has.
        XCTAssertEqual(sessions[1].label, "Paired browser")
        XCTAssertEqual(sessions[1].scope, "read")
        XCTAssertNil(sessions[1].expiresAt)
    }

    func testRevokingUsesDelete() async throws {
        let (api, transport) = client(["/v1/auth/sessions/one": #"{"data":{"revoked":"one"},"meta":{}}"#])
        try await api.revokeWebSession(id: "one")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/v1/auth/sessions/one")
    }

    func testTimestampsWithFractionalSecondsParse() {
        // The server sends Python's `datetime.isoformat()`, which the default
        // ISO8601 formatter refuses outright — every date read as nil until this
        // was handled, so a paired browser had no expiry to show.
        XCTAssertNotNil(BackendPairingDate.parse("2026-08-22T21:17:20.661899+00:00"))
        XCTAssertNotNil(BackendPairingDate.parse("2026-08-22T21:17:20Z"))
        XCTAssertNil(BackendPairingDate.parse("tomorrow"))
        XCTAssertNil(BackendPairingDate.parse(nil))
    }
}

/// Records what was sent, and how often.
private final class PairingStubTransport: HTTPTransport, @unchecked Sendable {
    private let responses: [String: String]
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?
    private(set) var attempts = 0

    init(responses: [String: String], statusCode: Int = 200) {
        self.responses = responses
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attempts += 1
        lastRequest = request
        let path = request.url?.path ?? ""
        let body = responses.first(where: { path.hasSuffix($0.key) })?.value
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: body == nil && statusCode == 200 ? 404 : statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data((body ?? "{}").utf8), response)
    }

    func decodedBody() -> [String: Any]? {
        guard let data = lastRequest?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
