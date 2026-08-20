import Charts
import SwiftUI

enum TessalyticsTheme {
    // Inspired by the Tesla Motors palette without reproducing the Tesla app.
    static let accent = Color(red: 0.80, green: 0.00, blue: 0.00)       // #CC0000
    static let accentBright = Color(red: 1.00, green: 0.26, blue: 0.26)
    static let graphite = Color(red: 0.13, green: 0.13, blue: 0.13)     // #212121
    static let neutral = Color.primary
    static let steel = Color(red: 0.51, green: 0.51, blue: 0.51)        // #818181
    static let mist = Color(red: 0.95, green: 0.95, blue: 0.95)         // #F2F2F2
    static let snow = Color(red: 0.98, green: 0.98, blue: 0.98)         // #FAFAFA

    // Green and amber remain reserved for semantic state, never decoration.
    static let positive = Color(red: 0.12, green: 0.58, blue: 0.34)
    static let warning = Color(red: 0.82, green: 0.43, blue: 0.08)
    static let critical = Color(red: 0.80, green: 0.00, blue: 0.00)

    /// Series colour for charts.
    ///
    /// `neutral` is `Color.primary`, which is correct for text but renders a data
    /// series as a solid black bar in light mode. Charts use this graphite
    /// instead, which reads as a colour rather than as ink.
    static let chartNeutral = Color(red: 0.29, green: 0.32, blue: 0.38)

    static let cardRadius: CGFloat = 16
    static let compactRadius: CGFloat = 12

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.055, green: 0.055, blue: 0.06) : snow
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.105, green: 0.105, blue: 0.115) : .white
    }

    static func raisedSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.15) : .white
    }

    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.10) : graphite.opacity(0.10)
    }
}

/// Single source of truth for spacing and card geometry so every screen reads as one system.
enum TessalyticsLayout {
    /// Vertical rhythm between stacked cards on a screen.
    static let stackSpacing: CGFloat = 12
    /// Gap between cells inside any metric or stat grid.
    static let gridSpacing: CGFloat = 8
    static let screenHorizontalPadding: CGFloat = 12
    static let screenVerticalPadding: CGFloat = 8

    /// Minimum widths for the adaptive grids. Wider screens simply gain columns.
    static let metricMinWidth: CGFloat = 116
    static let statMinWidth: CGFloat = 96
    static let stateMinWidth: CGFloat = 132

    /// Cards stop growing past this width so a 13-inch iPad does not stretch a
    /// four-character value across half a metre of glass.
    static let readableWidth: CGFloat = 760
    /// Wider ceiling for screens whose primary content is a chart or a map.
    static let wideReadableWidth: CGFloat = 1_040

    static func metricColumns(minimum: CGFloat = metricMinWidth) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: gridSpacing)]
    }
}

/// Centres and width-limits scrolling content. Without this, every card on an
/// iPad stretches edge to edge and the screens stop looking like the phone app.
private struct ReadableWidthModifier: ViewModifier {
    let maximum: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maximum)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Constrains content to a comfortable reading width and centres it.
    func tessalyticsReadableWidth(_ maximum: CGFloat = TessalyticsLayout.readableWidth) -> some View {
        modifier(ReadableWidthModifier(maximum: maximum))
    }

    /// Standard page padding used by every scrolling screen.
    func tessalyticsScreenPadding() -> some View {
        padding(.horizontal, TessalyticsLayout.screenHorizontalPadding)
            .padding(.vertical, TessalyticsLayout.screenVerticalPadding)
    }
}

/// Uniform grid for `MetricCard`s. Using one component everywhere keeps column
/// widths and gutters identical across the app.
struct MetricGrid<Content: View>: View {
    var minimumWidth: CGFloat = TessalyticsLayout.metricMinWidth
    @ViewBuilder let content: Content

    init(minimumWidth: CGFloat = TessalyticsLayout.metricMinWidth, @ViewBuilder content: () -> Content) {
        self.minimumWidth = minimumWidth
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: TessalyticsLayout.metricColumns(minimum: minimumWidth),
            spacing: TessalyticsLayout.gridSpacing
        ) {
            content
        }
    }
}

struct TessalyticsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var showsTopAccent = true
    /// A stronger wash and a thicker accent, so a glance says the screen is live.
    ///
    /// Deliberately a shift in the existing palette rather than a different one:
    /// the app should look like itself in a different mode, not like a different
    /// app, and a driver has no attention to spare for relearning a layout.
    var isLive = false

    private var wash: Color { isLive ? TessalyticsTheme.accentBright : TessalyticsTheme.accent }

    private func liveScaled(dark: Double, light: Double) -> Double {
        let base = colorScheme == .dark ? dark : light
        return isLive ? base * 2.4 : base
    }

    var body: some View {
        ZStack {
            TessalyticsTheme.canvas(for: colorScheme)
            LinearGradient(
                colors: [
                    wash.opacity(liveScaled(dark: 0.10, light: 0.055)),
                    TessalyticsTheme.graphite.opacity(colorScheme == .dark ? 0.05 : 0.018),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if showsTopAccent {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(wash)
                        .frame(height: isLive ? 4 : 2)
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLive)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct TessalyticsScreen<Content: View>: View {
    var showsTopAccent = true
    var isLive = false
    @ViewBuilder let content: Content

    init(showsTopAccent: Bool = true, isLive: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsTopAccent = showsTopAccent
        self.isLive = isLive
        self.content = content()
    }

    var body: some View {
        ZStack {
            TessalyticsBackdrop(showsTopAccent: showsTopAccent, isLive: isLive)
            content
        }
    }
}

struct SurfaceCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = TessalyticsTheme.accent
    @ViewBuilder let content: Content

    init(tint: Color = TessalyticsTheme.accent, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TessalyticsTheme.cardRadius, style: .continuous)

        content
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TessalyticsTheme.surface(for: colorScheme), in: shape)
            .overlay {
                shape
                    .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(tint)
                    .frame(width: 24, height: 2)
                    .padding(.leading, 13)
                    .accessibilityHidden(true)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.20 : 0.045),
                radius: colorScheme == .dark ? 8 : 5,
                y: 2
            )
    }
}

struct TessalyticsHeroSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = TessalyticsTheme.accent
    @ViewBuilder let content: Content

    init(tint: Color = TessalyticsTheme.accent, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TessalyticsTheme.surface(for: colorScheme), in: shape)
            .overlay {
                LinearGradient(
                    colors: [tint.opacity(colorScheme == .dark ? 0.12 : 0.055), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .topLeading) {
                LinearGradient(
                    colors: [tint, tint.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 3)
                .clipShape(.capsule)
                .padding(.horizontal, 16)
            }
            .overlay {
                shape
                    .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                    .accessibilityHidden(true)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.18 : 0.055),
                radius: colorScheme == .dark ? 8 : 6,
                y: 3
            )
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = TessalyticsTheme.accent
    /// Draws a trailing chevron so a tappable card looks tappable.
    var showsDisclosure = false
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color = TessalyticsTheme.accent,
        showsDisclosure: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.showsDisclosure = showsDisclosure
        self.content = content()
    }

    var body: some View {
        SurfaceCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(title, systemImage: symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .tint(tint)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                content
            }
        }
    }
}

/// A `SectionCard` that pushes a destination. Used on the dashboard so each
/// summary card leads to the screen that explains it.
struct NavigationSectionCard<Destination: View, Content: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = TessalyticsTheme.accent
    @ViewBuilder let destination: Destination
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color = TessalyticsTheme.accent,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.destination = destination()
        self.content = content()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SectionCard(title, subtitle: subtitle, symbol: symbol, tint: tint, showsDisclosure: true) {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased()) detail")
    }
}

/// Square-ish shortcut tile for the dashboard's navigation row.
struct QuickLinkTile<Destination: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let symbol: String
    var tint: Color = TessalyticsTheme.accent
    @ViewBuilder let destination: Destination

    init(
        _ title: String,
        symbol: String,
        tint: Color = TessalyticsTheme.accent,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                TessalyticsTheme.raisedSurface(for: colorScheme),
                in: .rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
                    .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: .capsule)
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(text)")
    }
}

/// Compact metric tile.
///
/// The layout is deliberately fixed: a title row pinned to the top, the value
/// pinned to the bottom, and an optional detail line under it. Combined with
/// `maxHeight: .infinity` every tile in a grid row renders at exactly the same
/// height and the values line up, whether or not a neighbour carries a detail.
struct MetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    let symbol: String
    var detail: String? = nil
    var tint: Color = TessalyticsTheme.accent

    @ScaledMetric(relativeTo: .caption) private var iconSize = 18.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 2)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
            // The detail row is always laid out, even when empty: without it a
            // card that has no detail centres its value differently from the one
            // beside it, and a row of cards stops lining up.
            Text(detail ?? " ")
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(detail == nil ? 0 : 1)
                .accessibilityHidden(detail == nil)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: .infinity, alignment: .topLeading)
        .background(
            TessalyticsTheme.raisedSurface(for: colorScheme),
            in: .rect(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TessalyticsTheme.compactRadius, style: .continuous)
                .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }

    // At accessibility sizes the icon steals room the title needs, so it drops out.
    @ViewBuilder private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            titleText
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: iconSize, height: iconSize)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
                titleText
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = TessalyticsTheme.accent
    var badge: String?

    @ScaledMetric(relativeTo: .title3) private var symbolSize = 44.0

    var body: some View {
        TessalyticsHeroSurface(tint: tint) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(eyebrow.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(tint)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(tint)
                                .background(tint.opacity(0.12), in: .capsule)
                        }
                    }
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: symbol)
                    .font(.system(size: symbolSize * 0.48, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: symbolSize, height: symbolSize)
                    .background(tint.opacity(0.10), in: .rect(cornerRadius: symbolSize * 0.3))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CompactStat: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = TessalyticsTheme.accent

    init(title: String, value: String, detail: String? = nil, tint: Color = TessalyticsTheme.accent) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail ?? " ")
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .opacity(detail == nil ? 0 : 1)
                .accessibilityHidden(detail == nil)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Leading-edge dismiss control for sheets.
///
/// Pushed screens use the system back button so the swipe-back gesture keeps
/// working; sheets have no system equivalent, so they get this instead. Placing
/// it top-leading means every "go back" affordance in the app sits in the same
/// corner regardless of how the screen was presented.
struct TessalyticsDismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var title = "Back"

    var body: some View {
        Button {
            dismiss()
        } label: {
            Label(title, systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .font(.body.weight(.regular))
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("dismiss-button")
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

struct LoadingPanel: View {
    let title: String
    var symbol = "arrow.triangle.2.circlepath"

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text("This can take a moment on a private network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .foregroundStyle(TessalyticsTheme.accent)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct OfflineBanner: View {
    var body: some View {
        Label("Offline — showing synchronized data", systemImage: "icloud.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TessalyticsTheme.warning)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(TessalyticsTheme.warning.opacity(0.12))
            .accessibilityIdentifier("offline-banner")
    }
}

/// Colour-keyed legend for charts.
///
/// Charts with a single series get no legend from Swift Charts, which leaves the
/// reader guessing what a bar or line represents and in which unit. This states
/// both explicitly.
struct ChartLegend: View {
    struct Item: Identifiable, Hashable {
        let label: String
        let color: Color
        var id: String { label }

        init(_ label: String, color: Color) {
            self.label = label
            self.color = color
        }
    }

    let items: [Item]

    init(_ items: [Item]) { self.items = items }
    init(_ label: String, color: Color) { self.items = [Item(label, color: color)] }

    var body: some View {
        // Wraps rather than truncating so a long series name stays readable.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { entries }
            VStack(alignment: .leading, spacing: 4) { entries }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: \(items.map(\.label).joined(separator: ", "))")
    }

    @ViewBuilder private var entries: some View {
        ForEach(items) { item in
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Axis titles applied identically to every chart in the app.
///
/// Swift Charts renders bare numbers by default, so a "230" on the y-axis could
/// be miles, kilowatt-hours, or minutes. Both axes are always named.
private struct ChartAxisTitles: ViewModifier {
    let xTitle: String
    let yTitle: String

    func body(content: Content) -> some View {
        content
            .chartXAxisLabel(position: .bottom, alignment: .center) {
                Text(xTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text(yTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
    }
}

extension View {
    /// Names both axes, including units, so a value can be read without guessing.
    func tessalyticsChartAxes(x xTitle: String, y yTitle: String) -> some View {
        modifier(ChartAxisTitles(xTitle: xTitle, yTitle: yTitle))
    }
}

private struct TessalyticsChartStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .chartPlotStyle { plotArea in
                plotArea
                    .background(
                        (colorScheme == .dark ? Color.white : TessalyticsTheme.graphite)
                            .opacity(colorScheme == .dark ? 0.035 : 0.025),
                        in: .rect(cornerRadius: 12, style: .continuous)
                    )
            }
    }
}

extension View {
    func tessalyticsChartStyle() -> some View {
        modifier(TessalyticsChartStyle())
    }
}

/// Whether a chart's value axis has to include zero.
///
/// A magnitude — speed, power, energy, distance — is read against zero, so the
/// axis keeps it and an area fill under the line means something. For a reading
/// where zero is not a meaningful floor, anchoring there spends the plot on a
/// range the data never visits: a pack that sits at 400 V, an elevation of 15 m,
/// or an outside temperature of 18 °C all collapse to a flat line against zero.
enum ChartBaseline: Sendable {
    /// Keep zero on the axis and fill the area beneath the line.
    case zero
    /// Frame the observed range instead, and draw the line alone.
    case focused
}

/// A padded domain over the observed values, for `ChartBaseline.focused`.
///
/// Returns nil when there is nothing to frame, which leaves the automatic domain
/// in place rather than inventing one.
func focusedChartDomain(for values: [Double]) -> ClosedRange<Double>? {
    guard let low = values.min(), let high = values.max() else { return nil }
    guard high > low else {
        // A constant series still needs a visible band, or the line lands on the
        // axis edge and reads as missing data.
        let padding = max(abs(low) * 0.01, 0.5)
        return (low - padding)...(high + padding)
    }
    let padding = (high - low) * 0.1
    return (low - padding)...(high + padding)
}

extension View {
    /// Applies a value-axis domain when there is one, and otherwise leaves the
    /// automatic domain alone.
    @ViewBuilder
    func chartValueDomain(_ domain: ClosedRange<Double>?) -> some View {
        if let domain {
            chartYScale(domain: domain)
        } else {
            self
        }
    }
}

/// One sample of a metric, paired with when it was recorded.
///
/// It carries its own identity rather than being keyed by date. Two samples can
/// legitimately share a timestamp — and when a parser loses sub-second precision
/// hundreds of them do — and a duplicate id in a `Chart` silently drops marks
/// instead of drawing them, which truncates the trace partway across the plot.
struct ChartSample: Identifiable, Sendable {
    let id: Int
    let date: Date
    let value: Double
}

/// Reduces a dense series to at most `limit` samples, keeping its extremes.
///
/// A drive logs several samples a second — 747 for a four-minute trip — into a
/// plot a few hundred points wide, so most marks land on a pixel another one
/// already occupies. Bucketing by position and keeping each bucket's lowest and
/// highest value caps the work without smoothing away the peaks that a mean
/// would: a hard acceleration stays visible.
func downsampled(_ samples: [ChartSample], limit: Int = 240) -> [ChartSample] {
    guard limit >= 4, samples.count > limit else { return samples }
    let buckets = limit / 2
    var reduced: [ChartSample] = []
    reduced.reserveCapacity(limit)
    for bucket in 0..<buckets {
        let start = samples.count * bucket / buckets
        let end = samples.count * (bucket + 1) / buckets
        guard start < end else { continue }
        let slice = samples[start..<end]
        guard let lowest = slice.min(by: { $0.value < $1.value }),
              let highest = slice.max(by: { $0.value < $1.value }) else { continue }
        // In recording order, so the line reads left to right.
        if lowest.id == highest.id {
            reduced.append(lowest)
        } else if lowest.id < highest.id {
            reduced.append(lowest)
            reduced.append(highest)
        } else {
            reduced.append(highest)
            reduced.append(lowest)
        }
    }
    return reduced
}
