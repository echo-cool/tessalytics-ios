import LinkPresentation
import SwiftData
import SwiftUI
import UIKit

/// Turns a page into a single tall image.
///
/// `ImageRenderer` lays a view out at whatever size it is proposed, so proposing
/// a fixed width and letting the height fall out is exactly the "long screenshot"
/// a scrolling page wants — there is no scrolling, stitching or seam involved.
@MainActor
enum PageShareRenderer {
    /// Drawn at three times the layout size, so the result is sharp when it lands
    /// in a message thread on a retina screen and still readable if someone zooms.
    static let scale: CGFloat = 3

    /// The tallest poster worth producing, in points.
    ///
    /// A page with two years of history behind it can lay out to tens of
    /// thousands of points, and at 3x that is a bitmap large enough to fail on
    /// device. Pages cap what they put in a poster; this is the backstop.
    static let maximumHeight: CGFloat = 6_000

    /// Renders a poster, already carrying whatever environment it needs.
    ///
    /// Generic over the whole view rather than over `SharePoster`'s content, so
    /// the caller can wrap it in `.environment(...)` first: `ImageRenderer` builds
    /// a detached view graph that inherits nothing from the screen, and any child
    /// reading an observable out of the environment traps if it was not put there.
    static func image(of poster: some View) -> UIImage? {
        let renderer = ImageRenderer(content: poster)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: SharePoster<AnyView>.width, height: nil)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// The image and the words that travel with it.
struct ShareArtifact: Identifiable {
    let id = UUID()
    /// Absent when there is nothing to draw — a destination, for instance, which
    /// is a link and not a page.
    let image: UIImage?
    let text: String
    let title: String

    /// Written where a share sheet wants a file name.
    var fileName: String {
        let stem = title.replacingOccurrences(of: " ", with: "-").lowercased()
        return "tessalytics-\(stem).png"
    }
}

/// The system share sheet, given both the picture and the sentence.
///
/// `ShareLink` would be tidier, but it carries one item: a recipient would get
/// the image without the summary or the summary without the image. Handing
/// `UIActivityViewController` both means Messages attaches the picture *and*
/// quotes the figures, and Mail gets a body.
struct ShareSheet: UIViewControllerRepresentable {
    let artifact: ShareArtifact

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = artifact.image == nil
            ? [artifact.text]
            : [SharePosterSource(artifact: artifact), artifact.text]
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Names the image properly and gives the sheet something to preview.
private final class SharePosterSource: NSObject, UIActivityItemSource {
    let artifact: ShareArtifact

    init(artifact: ShareArtifact) {
        self.artifact = artifact
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        artifact.image ?? artifact.text
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType type: UIActivity.ActivityType?
    ) -> Any? {
        // A file URL where one is wanted, so the attachment arrives named rather
        // than as "Image.png".
        guard let image = artifact.image, let data = image.pngData() else { return artifact.text }
        let url = FileManager.default.temporaryDirectory.appending(path: artifact.fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return image
        }
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType type: UIActivity.ActivityType?
    ) -> String {
        artifact.title
    }

    /// What the sheet shows at the top.
    ///
    /// Without this the sheet previews whichever item it likes — which, with a
    /// summary travelling beside the picture, is the summary, so the owner taps
    /// share and sees a page of text where their car should be.
    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = artifact.title
        if let image = artifact.image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}

/// Puts a share button in the top right of a screen and renders the poster when
/// it is tapped.
///
/// Rendering happens on the tap rather than up front: a poster is a full-page
/// layout at three times scale, and doing that for every screen the owner merely
/// visits would be work nobody asked for.
struct ShareablePageModifier<PosterContent: View>: ViewModifier {
    // Re-injected into the rendered poster. ImageRenderer's view graph is
    // detached from the screen's, so anything the page's own views read out of
    // the environment has to be put back or they trap on a missing value.
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    let page: () -> SharePage
    /// Work the poster needs done before it can be drawn — in practice, fetching
    /// map tiles. Run on the tap rather than when the screen appears: a page nobody
    /// shares should not be downloading anything.
    let prepare: () async -> Void
    @ViewBuilder let posterContent: () -> PosterContent

    @State private var artifact: ShareArtifact?
    @State private var isRendering = false
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: share) {
                        if isRendering {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isRendering)
                    .accessibilityLabel("Share this page")
                    .accessibilityIdentifier("share-page")
                }
            }
            .sheet(item: $artifact) { ShareSheet(artifact: $0) }
            .alert(
                "Could not build the image",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func share() {
        guard !isRendering else { return }
        isRendering = true
        // A frame later, so the button's spinner is on screen before the main
        // actor is busy laying out a very tall view.
        Task { @MainActor in
            defer { isRendering = false }
            await prepare()
            let described = page()
            let poster = SharePoster(page: described, content: posterContent)
                .environment(appEnvironment)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
                .modelContext(modelContext)
            guard let image = PageShareRenderer.image(of: poster) else {
                failure = "This page could not be drawn as an image."
                return
            }
            artifact = ShareArtifact(
                image: image,
                text: described.summary.isEmpty ? described.title : described.summary,
                title: described.title
            )
        }
    }
}

extension View {
    /// Adds a share button to the top right that shares this page as one tall
    /// image, watermarked, with a written summary beside it.
    ///
    /// - Parameters:
    ///   - page: the title, subtitle, highlights and summary, read at the moment
    ///     of sharing so they reflect what is on screen rather than what was
    ///     there when the screen was built.
    ///   - poster: the content to draw. Usually the same expression the screen
    ///     scrolls, which is why pages factor that into a property.
    ///   - prepare: anything the poster needs fetched first, such as map tiles.
    func shareablePage<PosterContent: View>(
        _ page: @escaping () -> SharePage,
        prepare: @escaping () async -> Void = {},
        @ViewBuilder poster: @escaping () -> PosterContent
    ) -> some View {
        modifier(ShareablePageModifier(page: page, prepare: prepare, posterContent: poster))
    }
}
