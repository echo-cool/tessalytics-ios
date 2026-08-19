import XCTest
@testable import Tessalytics

final class APIClientTests: XCTestCase {
    func testBearerAuthenticationAndPagination() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertTrue(request.url!.query!.contains("page=2")); XCTAssertTrue(request.url!.query!.contains("show=30"))
            return (try Self.fixture("drives"), Self.response(request, 200))
        }
        let client = TeslaMateAPIClient(baseURL: URL(string: "https://example.test")!, authentication: .bearer("secret"), transport: transport)
        let data = try await client.drives(carID: 1, page: 2, show: 30, filter: .init())
        XCTAssertEqual(data.drives.count, 2)
    }

    func testBasicAuthentication() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjpwYXNz")
            return (Data("{\"data\":{\"cars\":[]}}".utf8), Self.response(request, 200))
        }
        _ = try await TeslaMateAPIClient(baseURL: URL(string: "https://example.test")!, authentication: .basic(username: "user", password: "pass"), transport: transport).cars()
    }

    func testStatusMappings() async {
        for (status, expected) in [(401, ClientError.badToken), (403, .forbidden), (404, .notFound)] {
            let client = makeStatusClient(status)
            do { _ = try await client.cars(); XCTFail("Expected failure") } catch { XCTAssertEqual(error as? ClientError, expected) }
        }
        for status in [502, 503, 504] {
            let client = makeStatusClient(status)
            do { _ = try await client.cars(); XCTFail("Expected failure") } catch { XCTAssertEqual(error as? ClientError, .backendUnavailable) }
        }
    }

    func testCancellation() async {
        let transport = MockTransport { request in try await Task.sleep(for: .seconds(10)); return (Data(), Self.response(request, 200)) }
        let client = TeslaMateAPIClient(baseURL: URL(string: "https://example.test")!, authentication: .none, transport: transport)
        let task = Task { try await client.cars() }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func makeStatusClient(_ status: Int) -> TeslaMateAPIClient {
        TeslaMateAPIClient(baseURL: URL(string: "https://example.test")!, authentication: .none,
                           transport: MockTransport { request in (Data(), Self.response(request, status)) })
    }
    private static func response(_ request: URLRequest, _ code: Int) -> HTTPURLResponse { HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)! }
    private static func fixture(_ name: String) throws -> Data { let bundle = Bundle(for: APIClientTests.self); return try Data(contentsOf: (bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: "json"))!) }
}

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) { self.handler = handler }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { try await handler(request) }
}
