import Foundation

/// Server-sent events carrying live vehicle state.
///
/// Polling is the wrong shape for a phone on a windscreen mount. At the
/// thirty-second interval the app used while parked, the speed on screen is wrong
/// almost all the time; at a one-second interval it spends the drive asking for
/// what it already has. The backend forwards MQTT's push all the way here, so a
/// reading appears when TeslaMate publishes it.
///
/// Reconnection is the stream's own business. A drive goes through tunnels and
/// dead cells, and a UI that has to re-establish its own connection ends up
/// showing a stale value with no indication that it stopped listening.
struct LiveStateStream: Sendable {
    let baseURL: URL
    let authentication: Authentication
    var session: URLSession = .shared
    /// Retry delays, in seconds. The last is reused for every attempt after it.
    var backoff: [UInt64] = [1, 2, 5, 10, 20]
    /// A connection that lasted at least this long was working, so the next drop
    /// starts the backoff again from one second.
    var backoffResetAfter: Duration = .seconds(20)
    /// The floor the server is asked to put between events, in seconds.
    ///
    /// Sent explicitly rather than left to the server's default: the whole point
    /// of the stream is that a reading reaches the screen at the rate TeslaMate
    /// produces it, which is roughly every 0.4s while driving, and that must not
    /// change under the app because a default moved.
    var minimumInterval: Double = 0.4
    /// How many events may wait for the UI.
    ///
    /// Small on purpose. Live telemetry is worth showing only while it is
    /// current, so a consumer that falls behind should skip to the newest reading
    /// rather than replay a queue of superseded ones — an unbounded buffer turns a
    /// momentary stall into a permanently growing lag.
    var bufferDepth = 8
    /// Handed every event body as it arrives, before it is decoded.
    ///
    /// Debug mode's window onto the wire. Given the raw bytes on purpose: the
    /// question it exists to answer is "is what the server sent what the app
    /// understood", and a recording of the app's own interpretation cannot
    /// answer it. Nil in normal use, and the stream does no extra work for it.
    var recorder: (@Sendable (Data) -> Void)?

    enum Event: Sendable {
        case state(StatusDataDTO)
        /// The stream dropped and is being re-established; the UI stops claiming
        /// the value on screen is current.
        case interrupted(String)
        case connected
    }

    func events(carID: Int) -> AsyncStream<Event> {
        AsyncStream(bufferingPolicy: .bufferingNewest(bufferDepth)) { continuation in
            let task = Task {
                let clock = ContinuousClock()
                var retries = RetrySchedule(delays: backoff, resetAfter: backoffResetAfter)
                while !Task.isCancelled {
                    let openedAt = clock.now
                    do {
                        try await readOnce(carID: carID, into: continuation)
                        // A clean end still means the stream is gone, so treat it
                        // as an interruption and reconnect.
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.interrupted(error.userFacingMessage))
                    }
                    guard !Task.isCancelled else { break }
                    let delay = retries.next(afterConnectionLasting: clock.now - openedAt)
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readOnce(carID: Int, into continuation: AsyncStream<Event>.Continuation) async throws {
        var components = URLComponents(
            url: baseURL.appending(path: "v1/vehicles/\(carID)/stream"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "min_interval", value: String(minimumInterval)),
            URLQueryItem(name: "units", value: TessalyticsBackendClient.unitSystem)
        ]
        guard let url = components?.url else { throw ClientError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // A proxy that decides to buffer would hold events until its buffer
        // filled, which is the one thing this endpoint cannot survive.
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // A stream has no natural end, so the usual per-request timeout would cut
        // it off mid-drive.
        request.timeoutInterval = 3_600
        authentication.apply(to: &request)

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClientError.forStatus(http.statusCode)
        }
        continuation.yield(.connected)

        var frames = EventFraming()
        // Bytes, not `bytes.lines`. `AsyncLineSequence` drops empty lines, and the
        // empty line is what ends a server-sent event — so every reading arrived,
        // was never terminated, and was silently discarded while the stream
        // reported itself connected. Verified: feeding "a\n\nb\n\n" through
        // `.lines` yields two lines and no blank.
        for try await byte in bytes {
            guard let body = frames.consume(byte: byte) else { continue }
            recorder?(body)
            guard let status = Self.decode(body: body, carID: carID) else { continue }
            if Task.isCancelled { throw CancellationError() }
            continuation.yield(.state(status))
        }
    }

    /// One event body as the app's status model.
    ///
    /// The same mapping the request route uses, deliberately: an event carries the
    /// body of `/state`, and a second interpretation of it is a second way for the
    /// numbers on screen to disagree with the car — or, as it did, for every
    /// reading to be discarded while the stream reported itself live.
    static func decode(body: Data, carID: Int, decoder: JSONDecoder = .tessalytics) -> StatusDataDTO? {
        try? decoder.decode(BackendEnvelope<BackendStateWrapperDTO>.self, from: body).statusData(carID: carID)
    }
}

/// Reassembles server-sent events from the bytes they arrive as.
///
/// Its own type, and fed bytes rather than lines, for one reason: an event ends
/// with a blank line, and `AsyncLineSequence` does not report blank lines. Built
/// on that, the framing waited forever for a terminator it could never see and
/// dropped every reading — with the connection up and the badge lit. Splitting
/// the bytes here is a dozen lines and it is testable without a socket.
struct EventFraming {
    private var event = Data()
    private var line = [UInt8]()

    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    /// Feeds one byte, returning a completed event body when this byte ended one.
    mutating func consume(byte: UInt8) -> Data? {
        guard byte == Self.lineFeed else {
            line.append(byte)
            return nil
        }
        // A CRLF stream is legal, and the CR is not part of the field value.
        if line.last == Self.carriageReturn { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        return consume(line: String(decoding: line, as: UTF8.self))
    }

    /// The body of a completed event, if this line completed one.
    mutating func consume(line: String) -> Data? {
        guard !line.isEmpty else {
            // A blank line ends an event.
            defer { event.removeAll(keepingCapacity: true) }
            return event.isEmpty ? nil : event
        }
        // Everything that is not a data line — `event:`, `id:`, `retry:`, and the
        // `:` comments that keep the connection and its proxies awake — is
        // deliberately ignored: this endpoint sends one kind of event.
        guard line.hasPrefix("data:") else { return nil }
        // Multiple data lines in one event are concatenated, newline separated, as
        // the specification requires.
        if !event.isEmpty { event.append(Self.lineFeed) }
        event.append(contentsOf: Array(line.dropFirst(5).drop(while: { $0 == " " }).utf8))
        return nil
    }
}

/// How long to wait before reconnecting.
///
/// A drive goes through tunnels, and each one ends the connection. Ageing the
/// backoff across those would leave the sixth tunnel followed by twenty seconds of
/// a stale speed on screen, so a connection that stayed up is not counted as a
/// failed attempt.
struct RetrySchedule {
    let delays: [UInt64]
    let resetAfter: Duration
    private var attempt = 0

    init(delays: [UInt64], resetAfter: Duration) {
        self.delays = delays.isEmpty ? [1] : delays
        self.resetAfter = resetAfter
    }

    mutating func next(afterConnectionLasting duration: Duration) -> UInt64 {
        if duration >= resetAfter { attempt = 0 }
        let delay = delays[min(attempt, delays.count - 1)]
        attempt += 1
        return delay
    }
}

extension ClientError {
    /// The error a status code maps to, shared with the request-based client.
    static func forStatus(_ code: Int) -> ClientError {
        switch code {
        case 401: .badToken
        case 403: .forbidden
        case 404: .notFound
        case 429: .rateLimited
        case 500...599: .backendUnavailable
        default: .unexpectedStatus(code)
        }
    }
}
