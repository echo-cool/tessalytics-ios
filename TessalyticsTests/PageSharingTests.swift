import SwiftUI
import XCTest
@testable import Tessalytics

/// A share here is a picture of a whole page, not a screenshot of a screen. The
/// difference is the thing worth testing: the image has to be taller than any
/// phone, drawn at a fixed width, and it has to contain the parts of the page
/// that were never scrolled into view.
@MainActor
final class PageSharingTests: XCTestCase {
    private func poster(rows: Int) -> SharePoster<some View> {
        SharePoster(
            page: SharePage(
                title: "Battery health",
                subtitle: "Aurora · 22 August 2026",
                highlights: [
                    .init(label: "health", value: "95.5%"),
                    .init(label: "capacity now", value: "74.9 kWh")
                ],
                summary: "Battery health for Aurora."
            )
        ) {
            VStack(spacing: 12) {
                ForEach(0..<rows, id: \.self) { index in
                    Text("Row \(index)")
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(.gray.opacity(0.2))
                }
            }
        }
    }

    func testAPosterIsRenderedAtAFixedWidthAndItsNaturalHeight() throws {
        let image = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 3)))
        XCTAssertEqual(
            image.size.width,
            SharePoster<AnyView>.width,
            accuracy: 1,
            "The width is fixed so a shared page always looks the same shape"
        )
        XCTAssertEqual(image.scale, PageShareRenderer.scale)
    }

    func testAPosterGrowsWithItsContentPastTheHeightOfAnyPhone() throws {
        // This is the whole feature: a page too long to see at once still shares
        // as one image.
        let short = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 2)))
        let long = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 40)))

        XCTAssertGreaterThan(long.size.height, short.size.height)
        XCTAssertGreaterThan(long.size.height, 1_200, "Taller than any phone screen")
        XCTAssertEqual(long.size.width, short.size.width, accuracy: 1, "However tall it gets")
    }

    func testTheRenderedPixelsAreThreeTimesTheLayout() throws {
        let image = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 3)))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(
            Double(cg.width),
            Double(SharePoster<AnyView>.width) * PageShareRenderer.scale,
            accuracy: 2,
            "A share that is soft in a message thread is not worth sending"
        )
    }

    func testAPosterIsOpaqueSoItDoesNotArriveOnABlackBackground() throws {
        let image = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 2)))
        let cg = try XCTUnwrap(image.cgImage)
        let info = cg.alphaInfo
        XCTAssertTrue(
            info == .noneSkipLast || info == .noneSkipFirst || info == .none,
            "Transparent PNGs composite onto black in most messaging apps"
        )
    }

    /// Writes a poster out so a person can look at it.
    ///
    /// Skipped unless asked for: the assertions above prove the mechanics, and
    /// what they cannot prove is whether the thing is nice to look at.
    func testWriteASamplePoster() throws {
        guard let path = ProcessInfo.processInfo.environment["TESSALYTICS_POSTER_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TESSALYTICS_POSTER_DIR to write a sample poster.")
        }
        let image = try XCTUnwrap(PageShareRenderer.image(of: poster(rows: 6)))
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appending(path: "poster.png"))
    }

    func testTheArtifactNamesItsFileAfterThePage() {
        let artifact = ShareArtifact(image: UIImage(), text: "…", title: "Battery health")
        XCTAssertEqual(artifact.fileName, "tessalytics-battery-health.png")
    }
}

/// The route is the most worthwhile thing on several of these pages, and
/// `ImageRenderer` cannot draw a `Map` — so the poster draws the tiles itself.
final class RoutePosterSnapshotTests: XCTestCase {
    private let route = [
        CoordinateDTO(latitude: 37.3861, longitude: -122.0839),
        CoordinateDTO(latitude: 37.4062, longitude: -122.0723)
    ]

    func testTheRegionCoversTheWholeRouteWithAMargin() throws {
        let region = try XCTUnwrap(RoutePosterSnapshot.region(for: route))
        XCTAssertEqual(region.center.latitude, 37.39615, accuracy: 0.0005)
        XCTAssertEqual(region.center.longitude, -122.0781, accuracy: 0.0005)
        XCTAssertGreaterThan(
            region.span.latitudeDelta,
            37.4062 - 37.3861,
            "Padded, so the line does not run into the edge of the frame"
        )
    }

    func testAVeryShortRouteStillGetsAReadableRegion() {
        // A drive around one car park spans almost nothing, and a map zoomed to
        // that is a grey rectangle.
        let tiny = [
            CoordinateDTO(latitude: 37.3861, longitude: -122.0839),
            CoordinateDTO(latitude: 37.38611, longitude: -122.08391)
        ]
        let region = RoutePosterSnapshot.region(for: tiny)
        XCTAssertEqual(region?.span.latitudeDelta, 0.004)
        XCTAssertEqual(region?.span.longitudeDelta, 0.004)
    }

    func testNoRouteIsNoRegionRatherThanACrash() {
        XCTAssertNil(RoutePosterSnapshot.region(for: []))
    }

    /// Writes a drawn route out so a person can look at it. Skipped unless asked
    /// for — it needs the network, because it fetches real map tiles.
    func testWriteASampleRoute() async throws {
        guard let path = ProcessInfo.processInfo.environment["TESSALYTICS_POSTER_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TESSALYTICS_POSTER_DIR to write a sample route.")
        }
        let curve = (0...40).map { step -> CoordinateDTO in
            let fraction = Double(step) / 40
            return CoordinateDTO(
                latitude: 37.3861 + fraction * 0.09 + sin(fraction * 6) * 0.004,
                longitude: -122.0839 - fraction * 0.11 + cos(fraction * 4) * 0.005
            )
        }
        let drawn = await RoutePosterSnapshot.snapshot(
            route: curve,
            size: CGSize(width: 380, height: 216),
            colorScheme: .light
        )
        let image = try XCTUnwrap(drawn)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appending(path: "route.png"))
    }
}
