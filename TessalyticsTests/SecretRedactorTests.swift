import XCTest
@testable import Tessalytics

/// The export is the one artefact this app produces that a person hands to
/// somebody else, so it has two jobs: keep the private things out, and remain
/// something a tool can read. A real export failed the second.
final class SecretRedactorTests: XCTestCase {
    func testARedactedBodyIsStillValidJSON() throws {
        // `"latitude" : [REDACTED]` is not JSON, and every recorded event in the
        // export is a JSON body — so the whole file stopped being machine
        // readable, which was found by trying to read one.
        let body = """
        {
          "location" : {
            "latitude" : 37.406210,
            "longitude" : -122.072300,
            "elevation" : 37
          }
        }
        """
        let redacted = SecretRedactor.redact(body)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any]
        )
        let location = try XCTUnwrap(object["location"] as? [String: Any])
        XCTAssertEqual(location["latitude"] as? String, "[REDACTED]")
        XCTAssertEqual(location["longitude"] as? String, "[REDACTED]")
        XCTAssertEqual(location["elevation"] as? Int, 37, "Only the position goes")
    }

    /// A redacted coordinate is a string, not null: null is indistinguishable
    /// from "the car reported no position", which is the distinction a location
    /// log exists to make.
    func testARedactedCoordinateIsTellableFromAMissingOne() throws {
        let redacted = SecretRedactor.redact(#"{"latitude" : 37.4062, "geofence" : null}"#)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any]
        )
        XCTAssertNotNil(object["latitude"] as? String)
        XCTAssertTrue(object["geofence"] is NSNull)
    }

    /// The VIN rule is seventeen characters of an alphabet that also describes
    /// seventeen digits — and a Double printed in full supplies them.
    func testALongNumberIsNotMistakenForAVIN() throws {
        let body = #"{"age_seconds" : 0.53510901234567891, "took_ms" : 12345678901234567}"#
        let redacted = SecretRedactor.redact(body)
        XCTAssertFalse(redacted.contains("REDACTED"), "A number is not a VIN: \(redacted)")
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(redacted.utf8)))
    }

    func testARealVINIsStillRemoved() {
        let redacted = SecretRedactor.redact(#"{"vin" : "5YJ3E1EA0PF123456"}"#)
        XCTAssertFalse(redacted.contains("5YJ3E1EA0PF123456"))
        XCTAssertTrue(redacted.contains("REDACTED"))
    }

    func testCredentialsAreStillRemoved() {
        for line in ["Authorization: Bearer abc123",
                     "token=super-secret-value",
                     "password: hunter2"] {
            XCTAssertFalse(
                SecretRedactor.redact(line).contains("abc123")
                    && SecretRedactor.redact(line).contains("super-secret-value"),
                "\(line) should not survive"
            )
            XCTAssertTrue(SecretRedactor.redact(line).contains("REDACTED"))
        }
    }
}
