import XCTest
@testable import Tessalytics

/// A value axis must frame the data, not a range the data never visits.
final class ChartDomainTests: XCTestCase {
    func testDomainFramesTheObservedRange() throws {
        // A pack under load sits near 400 V; anchoring that axis to zero hides
        // every change worth seeing.
        let domain = try XCTUnwrap(focusedChartDomain(for: [382, 394, 401, 418]))
        XCTAssertEqual(domain.lowerBound, 378.4, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 421.6, accuracy: 0.001)
        XCTAssertFalse(domain.contains(0))
    }

    func testDomainPadsByATenthOfTheSpan() throws {
        let domain = try XCTUnwrap(focusedChartDomain(for: [15, 20]))
        XCTAssertEqual(domain.lowerBound, 14.5, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 20.5, accuracy: 0.001)
    }

    func testAConstantSeriesStillGetsAVisibleBand() throws {
        // Otherwise the line lands exactly on the axis edge and reads as missing.
        let domain = try XCTUnwrap(focusedChartDomain(for: [18.5, 18.5, 18.5]))
        XCTAssertLessThan(domain.lowerBound, 18.5)
        XCTAssertGreaterThan(domain.upperBound, 18.5)
    }

    func testNoValuesLeavesTheAutomaticDomainAlone() {
        XCTAssertNil(focusedChartDomain(for: []))
    }

    func testNegativeValuesAreFramedToo() throws {
        // Elevation below sea level, or a temperature below freezing.
        let domain = try XCTUnwrap(focusedChartDomain(for: [-12, -4]))
        XCTAssertEqual(domain.lowerBound, -12.8, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, -3.2, accuracy: 0.001)
    }
}

// MARK: - Downsampling

extension ChartDomainTests {
    private func makeSamples(_ values: [Double]) -> [ChartSample] {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return values.enumerated().map {
            ChartSample(id: $0.offset, date: base.addingTimeInterval(Double($0.offset) * 0.3), value: $0.element)
        }
    }

    func testAShortSeriesIsLeftAlone() {
        let samples = makeSamples((0..<50).map(Double.init))
        XCTAssertEqual(downsampled(samples, limit: 240).map(\.id), samples.map(\.id))
    }

    func testDenseSeriesIsCappedAtTheLimit() {
        let samples = makeSamples((0..<747).map { Double($0 % 40) })
        let reduced = downsampled(samples, limit: 240)
        XCTAssertLessThanOrEqual(reduced.count, 240)
        XCTAssertGreaterThan(reduced.count, 100, "Enough marks must survive to keep the shape")
    }

    func testPeaksSurviveDownsampling() {
        // A single hard acceleration in an otherwise slow drive: a mean would
        // smooth it away, and the chart would contradict the "maximum speed" card.
        var values = [Double](repeating: 5, count: 747)
        values[400] = 92
        values[401] = 88
        let reduced = downsampled(makeSamples(values), limit: 240)
        XCTAssertEqual(reduced.map(\.value).max(), 92)
        XCTAssertEqual(reduced.map(\.value).min(), 5)
    }

    func testDownsamplingKeepsRecordingOrder() {
        let values = (0..<747).map { Double(($0 * 37) % 91) }
        let reduced = downsampled(makeSamples(values), limit: 240)
        XCTAssertEqual(reduced.map(\.id), reduced.map(\.id).sorted(), "Marks must stay in time order")
        XCTAssertEqual(reduced.map(\.date), reduced.map(\.date).sorted())
    }

    func testDownsampledMarksKeepDistinctIdentities() {
        let reduced = downsampled(makeSamples((0..<747).map { Double($0 % 17) }), limit: 240)
        XCTAssertEqual(Set(reduced.map(\.id)).count, reduced.count, "A duplicate id drops a mark")
    }

    func testTheFirstAndLastBucketsAreRepresented() {
        let values = (0..<747).map { Double($0) }
        let reduced = downsampled(makeSamples(values), limit: 240)
        // A rising series: the extremes are the very first and very last samples.
        XCTAssertEqual(reduced.first?.value, 0)
        XCTAssertEqual(reduced.last?.value, 746)
    }
}
