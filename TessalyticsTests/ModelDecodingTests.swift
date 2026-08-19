import XCTest
@testable import Tessalytics

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder.tessalytics

    func testGenericEnvelopeSnakeCaseUnknownAndMissingFields() throws {
        let data = try fixture("cars")
        let envelope = try decoder.decode(Envelope<CarsDataDTO>.self, from: data)
        XCTAssertEqual(envelope.data.cars.count, 2)
        XCTAssertEqual(envelope.data.cars[0].carId, 1)
        XCTAssertNil(envelope.data.cars[0].carDetails?.trimBadging)
        XCTAssertNil(envelope.data.cars[1].name)
    }

    func testNullsMixedUnitsAndInvalidScheduledDate() throws {
        let envelope = try decoder.decode(Envelope<StatusDataDTO>.self, from: fixture("status"))
        XCTAssertEqual(envelope.data.units?.unitOfLength, "mi")
        XCTAssertEqual(envelope.data.units?.unitOfPressure, "psi")
        XCTAssertEqual(envelope.data.units?.unitOfTemperature, "C")
        XCTAssertNil(envelope.data.status.climateDetails?.insideTemp)
        XCTAssertNil(envelope.data.status.chargingDetails?.scheduledChargingStartTime?.value)
    }

    func testRFC3339AndFractionalDates() throws {
        XCTAssertNotNil(FlexibleDateParser.date(from: "2026-08-18T21:28:22-07:00"))
        XCTAssertNotNil(FlexibleDateParser.date(from: "2026-08-18T21:28:22.123Z"))
        XCTAssertNil(FlexibleDateParser.date(from: "0000-12-31T16:07:02-07:52"))
    }

    func testInProgressAndCompletedHistory() throws {
        let drives = try decoder.decode(Envelope<DrivesDataDTO>.self, from: fixture("drives")).data.drives
        let charges = try decoder.decode(Envelope<ChargesDataDTO>.self, from: fixture("charges")).data.charges
        XCTAssertNotNil(drives[0].endDate?.value); XCTAssertNil(drives[1].endDate?.value)
        XCTAssertNotNil(charges[0].endDate?.value); XCTAssertNil(charges[1].endDate?.value)
        XCTAssertNil(charges[0].cost)
    }

    func testInvalidServerResponseFails() {
        XCTAssertThrowsError(try decoder.decode(Envelope<CarsDataDTO>.self, from: Data("{broken".utf8)))
    }

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
