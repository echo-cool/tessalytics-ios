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

struct TessalyticsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var showsTopAccent = true

    var body: some View {
        ZStack {
            TessalyticsTheme.canvas(for: colorScheme)
            LinearGradient(
                colors: [
                    TessalyticsTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.055),
                    TessalyticsTheme.graphite.opacity(colorScheme == .dark ? 0.05 : 0.018),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if showsTopAccent {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(TessalyticsTheme.accent)
                        .frame(height: 2)
                    Spacer(minLength: 0)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct TessalyticsScreen<Content: View>: View {
    var showsTopAccent = true
    @ViewBuilder let content: Content

    init(showsTopAccent: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsTopAccent = showsTopAccent
        self.content = content()
    }

    var body: some View {
        ZStack {
            TessalyticsBackdrop(showsTopAccent: showsTopAccent)
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
            .background(
                LinearGradient(
                    colors: [TessalyticsTheme.graphite, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: shape
            )
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
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = TessalyticsTheme.accent
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color = TessalyticsTheme.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        SurfaceCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.hierarchical)
                        .tint(tint)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                content
            }
        }
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

struct MetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let symbol: String
    var detail: String? = nil
    var tint: Color = TessalyticsTheme.accent

    @ScaledMetric(relativeTo: .body) private var iconSize = 28.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
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
                            .foregroundStyle(TessalyticsTheme.accentBright)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.12), in: .capsule)
                        }
                    }
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: symbol)
                    .font(.system(size: symbolSize * 0.48, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TessalyticsTheme.accentBright)
                    .frame(width: symbolSize, height: symbolSize)
                    .background(.white.opacity(0.10), in: .rect(cornerRadius: symbolSize * 0.3))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CompactStat: View {
    let title: String
    let value: String
    var tint: Color = TessalyticsTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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

struct TessalyticsBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(TessalyticsTheme.accent)
        .accessibilityLabel("Back")
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
