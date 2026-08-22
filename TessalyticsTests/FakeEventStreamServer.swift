import Foundation
import Network

/// A loopback HTTP server that speaks `text/event-stream`.
///
/// Exists because every unit test of the stream passed while the feature was
/// completely broken. The framing was tested against strings the test itself
/// produced, and the one thing nobody tested was whether the bytes a real server
/// sends, read back through a real `URLSession`, ever became a reading. They did
/// not: `AsyncLineSequence` does not report the blank line that ends an event, so
/// every reading was discarded with the connection up and the badge lit.
///
/// So this serves real bytes over a real socket, and the tests assert that a
/// reading comes out the other end.
/// Safe to hand to the sending closures, which run off the test's thread: every
/// piece of mutable state lives behind the lock in `State`.
final class FakeEventStreamServer: @unchecked Sendable {
    /// The port the listener bound to.
    private(set) var port: UInt16 = 0

    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-sse-server")
    private let ready = DispatchSemaphore(value: 0)
    private let connected = DispatchSemaphore(value: 0)

    private let state = State()

    /// Guards the connection and the recorded request across the listener's queue
    /// and the test's thread.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var connection: NWConnection?
        private var request = Data()

        func adopt(_ connection: NWConnection) {
            lock.lock(); defer { lock.unlock() }
            self.connection = connection
        }

        func current() -> NWConnection? {
            lock.lock(); defer { lock.unlock() }
            return connection
        }

        func append(request bytes: Data) {
            lock.lock(); defer { lock.unlock() }
            request.append(bytes)
        }

        func requestText() -> String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: request, as: UTF8.self)
        }
    }

    /// - Parameter statusLine: overridden by the tests that need a failure.
    init(statusLine: String = "HTTP/1.1 200 OK") throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [state, queue] connection in
            connection.start(queue: queue)
            // Read the request first, and route on it. The app makes other requests
            // to the same host — it fetches the drive's route while driving — and
            // treating whichever socket arrived last as the event stream sends the
            // readings down the wrong connection.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { data, _, _, _ in
                if let data { state.append(request: data) }
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                guard request.contains("/stream") else {
                    let notFound = [
                        "HTTP/1.1 404 Not Found",
                        "Content-Type: application/json",
                        "Content-Length: 2",
                        "Connection: close",
                        "",
                        "{}"
                    ].joined(separator: "\r\n")
                    connection.send(
                        content: Data(notFound.utf8),
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                    return
                }
                state.adopt(connection)
                let isSuccess = statusLine.contains(" 200 ")
                var headers = [statusLine, "Cache-Control: no-store", "Connection: close"]
                if isSuccess {
                    headers.append("Content-Type: text/event-stream")
                } else {
                    // A refusal is a complete response. Without a length,
                    // `URLSession` waits for a body that is never coming and the
                    // failure looks like a hang rather than a 401.
                    headers.append("Content-Type: application/json")
                    headers.append("Content-Length: 0")
                }
                headers.append(contentsOf: ["", ""])
                connection.send(
                    content: Data(headers.joined(separator: "\r\n").utf8),
                    completion: isSuccess ? .idempotent : .contentProcessed { _ in connection.cancel() }
                )
            }
        }
        listener.stateUpdateHandler = { [ready] state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let bound = listener.port else {
            throw Failure.didNotStart
        }
        port = bound.rawValue
    }

    enum Failure: Error { case didNotStart, noConnection }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Whether a client has connected to the event stream yet.
    ///
    /// Tests wait on this rather than sleeping. Sleeping is worse than slow here:
    /// the app's stream loop runs on the main actor, so a test that blocks the main
    /// thread waiting for a connection prevents the connection from ever being
    /// made, and the deadlock reads as a broken app.
    var hasClient: Bool { state.current() != nil }

    /// The request line and headers the client sent, once it has connected.
    func recordedRequest(timeout: TimeInterval = 5) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, state.current() == nil {
            usleep(20_000)
        }
        // The receive handler runs a moment after the connection appears.
        usleep(120_000)
        return state.requestText()
    }

    /// Writes one complete `state` event, blank line and all.
    func send(state json: String) {
        write("event: state\ndata: \(json)\n\n")
    }

    /// A keep-alive comment, which must not be mistaken for a reading.
    func sendKeepAlive() {
        write(": keep-alive\n\n")
    }

    /// Raw bytes, for the tests that split an event across two writes.
    ///
    /// Never blocks: see `hasClient`.
    func write(_ text: String) {
        state.current()?.send(content: Data(text.utf8), completion: .idempotent)
    }

    /// Drops the connection, as a tunnel does.
    func dropConnection() {
        state.current()?.cancel()
    }

    func stop() {
        state.current()?.cancel()
        listener.cancel()
    }
}
