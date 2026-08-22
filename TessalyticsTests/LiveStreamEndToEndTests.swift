import XCTest
@testable import Tessalytics

/// The stream read end to end: real bytes, a real socket, a real `URLSession`.
///
/// This is the test that was missing. Every piece of the stream had unit tests and
/// the feature had never once delivered a reading, because the piece nobody
/// covered was the join between `URLSession`'s bytes and the framing — where
/// `AsyncLineSequence` was quietly dropping the blank line that ends an event.
final class LiveStreamEndToEndTests: XCTestCase {
    private var server: FakeEventStreamServer!

    override func setUpWithError() throws {
        server = try FakeEventStreamServer()
    }

    override func tearDown() {
        server.stop()
        server = nil
    }

    private func stream(_ server: FakeEventStreamServer) -> LiveStateStream {
        var stream = LiveStateStream(baseURL: server.baseURL, authentication: .bearer("token"))
        // A test must not wait out a production backoff.
        stream.backoff = [1]
        return stream
    }

    /// Waits for the server to have a client, without blocking a thread the
    /// client's own task may need.
    private func waitForClient(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !server.hasClient {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func body(speed: Double, level: Int = 71) -> String {
        """
        {"data":{"state":{"vehicle_id":1,"state":"driving","state_since":"2026-08-21T04:12:19Z",
        "name":"wyy","location":{"latitude":37.36,"longitude":-121.98,"heading":120},
        "battery":{"level":\(level),"usable_level":\(level),"range":234.8},
        "driving":{"shift_state":"D","speed":\(speed),"power":34.0,"odometer":33938.4}}},
        "meta":{"source":"mixed","units":{"length":"mi","temperature":"C","pressure":"psi","range":"rated"}}}
        """.replacingOccurrences(of: "\n", with: "")
    }

    /// Collects events until `count` state readings have arrived, or the timeout.
    private func collect(
        _ count: Int,
        from stream: LiveStateStream,
        timeout: TimeInterval = 10,
        while sending: @escaping @Sendable () -> Void
    ) async -> [LiveStateStream.Event] {
        let source = stream.events(carID: 1)
        let collector = Task { () -> [LiveStateStream.Event] in
            var events: [LiveStateStream.Event] = []
            for await event in source {
                events.append(event)
                if events.filter(\.isState).count >= count { break }
            }
            return events
        }
        // Only once the client has actually connected. Sending into a listener with
        // no client writes the events nowhere, which under load — the whole suite
        // running at once — turns these into flakes rather than tests.
        await waitForClient()
        Task.detached { sending() }
        let deadline = Task {
            try await Task.sleep(for: .seconds(timeout))
            collector.cancel()
        }
        let events = await collector.value
        deadline.cancel()
        return events
    }

    func testAReadingSentByTheServerReachesTheClient() async throws {
        let events = await collect(1, from: stream(server)) { [server] in
            server?.send(state: Self.body(speed: 63))
        }

        let states = events.compactMap(\.state)
        XCTAssertEqual(states.count, 1, "A single event must produce a single reading")
        XCTAssertEqual(states.first?.status.drivingDetails?.speed, 63)
        XCTAssertTrue(states.first?.status.isDriving == true)
        XCTAssertTrue(events.contains { $0.isConnected }, "The connection is reported before the reading")
    }

    func testEveryReadingArrivesRatherThanOnlyTheFirst() async throws {
        // The whole point of the stream: a drive is a sequence of readings.
        let events = await collect(4, from: stream(server)) { [server] in
            for speed in [10.0, 20.0, 30.0, 40.0] {
                server?.send(state: Self.body(speed: speed))
                usleep(60_000)
            }
        }
        XCTAssertEqual(events.compactMap(\.state).compactMap { $0.status.drivingDetails?.speed }, [10, 20, 30, 40])
    }

    func testAKeepAliveIsNotMistakenForAReading() async throws {
        let events = await collect(1, from: stream(server)) { [server] in
            server?.sendKeepAlive()
            usleep(80_000)
            server?.sendKeepAlive()
            usleep(80_000)
            server?.send(state: Self.body(speed: 55))
        }
        XCTAssertEqual(events.compactMap(\.state).count, 1)
        XCTAssertEqual(events.compactMap(\.state).first?.status.drivingDetails?.speed, 55)
    }

    func testAnEventSplitAcrossTwoWritesIsStillOneReading() async throws {
        // TCP does not respect message boundaries, so a reading can and does
        // arrive in pieces.
        let body = Self.body(speed: 47)
        let split = body.index(body.startIndex, offsetBy: body.count / 2)
        let events = await collect(1, from: stream(server)) { [server] in
            server?.write("event: state\ndata: \(body[..<split])")
            usleep(120_000)
            server?.write("\(body[split...])\n\n")
        }
        XCTAssertEqual(events.compactMap(\.state).first?.status.drivingDetails?.speed, 47)
    }

    func testTheRequestAsksForAnEventStreamAtTheRateTheDataArrives() async throws {
        let events = stream(server).events(carID: 1)
        let collector = Task {
            for await _ in events { break }
        }
        let request = server.recordedRequest()
        collector.cancel()

        XCTAssertTrue(request.contains("GET /v1/vehicles/1/stream"), request)
        XCTAssertTrue(request.contains("min_interval=0.4"), "The app pins the rate rather than inheriting a default")
        XCTAssertTrue(request.contains("units=teslamate"), "Both routes must report on one scale")
        XCTAssertTrue(request.lowercased().contains("accept: text/event-stream"), request)
        XCTAssertTrue(request.contains("Authorization: Bearer token"), "Every route needs the token")
    }

    func testADroppedConnectionIsReportedAndReconnected() async throws {
        let events = await collect(2, from: stream(server), timeout: 15) { [server] in
            server?.send(state: Self.body(speed: 30))
            usleep(200_000)
            server?.dropConnection()
            // The retry schedule's first delay is a second, so the reconnected
            // client is not there to receive anything before then.
            usleep(1_800_000)
            // The client reconnects to the same listener, which serves it again.
            server?.send(state: Self.body(speed: 35))
        }
        XCTAssertEqual(events.compactMap(\.state).count, 2, "The reading after the drop arrives too")
        XCTAssertEqual(events.filter(\.isConnected).count, 2, "Each connection is reported")
    }

    func testARejectedRequestIsSurfacedRatherThanLookingLive() async throws {
        let unauthorised = try FakeEventStreamServer(statusLine: "HTTP/1.1 401 Unauthorized")
        defer { unauthorised.stop() }

        let stream = stream(unauthorised).events(carID: 1)
        let collector = Task { () -> [LiveStateStream.Event] in
            var seen: [LiveStateStream.Event] = []
            for await event in stream {
                seen.append(event)
                if event.isInterrupted { break }
            }
            return seen
        }
        let deadline = Task { try await Task.sleep(for: .seconds(10)); collector.cancel() }
        let events = await collector.value
        deadline.cancel()

        XCTAssertTrue(events.contains(where: \.isInterrupted), "A 401 must not read as connected")
        XCTAssertFalse(events.contains(where: \.isConnected))
    }
}

private extension LiveStateStream.Event {
    var state: StatusDataDTO? {
        if case .state(let payload) = self { return payload }
        return nil
    }
    var isState: Bool { state != nil }
    var isConnected: Bool { if case .connected = self { return true } else { return false } }
    var isInterrupted: Bool { if case .interrupted = self { return true } else { return false } }
}
