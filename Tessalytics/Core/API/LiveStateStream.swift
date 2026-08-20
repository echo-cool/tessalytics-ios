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

    enum Event: Sendable {
        case state(StatusDataDTO)
        /// The stream dropped and is being re-established; the UI stops claiming
        /// the value on screen is current.
        case interrupted(String)
        case connected
    }

    func events(carID: Int) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    do {
                        try await readOnce(carID: carID, into: continuation)
                        // A clean end still means the stream is gone, so treat it
                        // as an interruption and reconnect.
                        attempt = 0
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.interrupted(error.userFacingMessage))
                    }
                    guard !Task.isCancelled else { break }
                    let delay = backoff[min(attempt, backoff.count - 1)]
                    attempt += 1
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readOnce(carID: Int, into continuation: AsyncStream<Event>.Continuation) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/vehicles/\(carID)/stream"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // A stream has no natural end, so the usual per-request timeout would cut
        // it off mid-drive.
        request.timeoutInterval = 3_600
        authentication.apply(to: &request)

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClientError.forStatus(http.statusCode)
        }
        continuation.yield(.connected)

        var data = Data()
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if line.isEmpty {
                // A blank line ends an event.
                defer { data.removeAll(keepingCapacity: true) }
                guard !data.isEmpty,
                      let payload = try? JSONDecoder.tessalytics.decode(Envelope<StatusDataDTO>.self, from: data)
                else { continue }
                continuation.yield(.state(payload.data))
            } else if line.hasPrefix("data:") {
                data.append(contentsOf: Array(line.dropFirst(5).drop(while: { $0 == " " }).utf8))
            }
            // Everything else — `event:`, `id:`, `:` comments — is deliberately
            // ignored: the event name is fixed and comments are keep-alives.
        }
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
