import SwiftUI

/// Whether a view is being drawn into a shareable image rather than onto the
/// screen.
///
/// The two are not the same picture. A poster has no navigation bar, no tab bar
/// and no scroll position — and, more awkwardly, `ImageRenderer` cannot draw a
/// `Map`, because MapKit renders through UIKit and the renderer only walks
/// SwiftUI's own layers. A view that shows a map on screen therefore has to show
/// something else here, and this is how it knows.
struct SharePosterRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isRenderingSharePoster: Bool {
        get { self[SharePosterRenderingKey.self] }
        set { self[SharePosterRenderingKey.self] = newValue }
    }
}

/// One fact worth putting at the top of a shared image.
struct ShareHighlight: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

/// What a page hands over to be shared.
struct SharePage: Equatable, Sendable {
    let title: String
    /// The line under the title: usually the car and the date.
    let subtitle: String
    /// The figures worth reading before the picture.
    var highlights: [ShareHighlight] = []
    /// The sentence that travels as text beside the image, for the places a
    /// picture is not enough — a message thread, a mail body, a search index.
    var summary: String = ""
}

extension SharePage {
    /// The line under the title on nearly every page: whose car, and when the
    /// picture was taken. The date matters — a shared figure is a figure as of a
    /// moment, and without one a screenshot outlives its own truth.
    static func subtitle(car: String?, date: Date = .now) -> String {
        let name = car?.nilIfEmpty ?? "Tesla"
        return "\(name) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// The image a share produces: the page, framed and signed.
///
/// Deliberately not a screenshot of the screen. A screenshot is whatever
/// happened to be scrolled into view, at whatever size the phone is, with a
/// status bar and a tab bar in it. This is the whole page at a fixed width,
/// which is what makes a long page shareable at all.
struct SharePoster<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let page: SharePage
    @ViewBuilder let content: Content

    /// The width the poster is laid out at, in points. Wide enough that two
    /// metric cards sit side by side, which is the layout the app was designed
    /// around.
    static var width: CGFloat { 420 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !page.highlights.isEmpty { highlights }
            content
            footer
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(TessalyticsTheme.canvas(for: colorScheme))
        .environment(\.isRenderingSharePoster, true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(TessalyticsTheme.accent)
                .frame(width: 44, height: 44)
                .background(TessalyticsTheme.accent.opacity(0.10), in: .rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(page.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// The figures, before the detail. Someone scrolling a message thread reads
    /// two numbers or none.
    private var highlights: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(page.highlights.prefix(4)) { highlight in
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlight.value)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(highlight.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            TessalyticsTheme.surface(for: colorScheme),
            in: .rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
        )
    }

    /// The watermark, bottom right.
    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TessalyticsTheme.accent)
            VStack(alignment: .trailing, spacing: 0) {
                Text("Tessalytics")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Live Vehicle Data")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
        .opacity(0.85)
    }
}
