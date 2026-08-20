import Charts
import SwiftUI

/// One plotted value, with the label it should carry on an axis and in a readout.
struct ExplorableChartPoint: Identifiable, Equatable, Sendable {
    let id: Int
    /// Short form for the axis, e.g. "Aug 14" or "Supercharger".
    let label: String
    /// Long form for the readout, when the short one loses information.
    var detail: String?
    let value: Double

    init(id: Int, label: String, detail: String? = nil, value: Double) {
        self.id = id
        self.label = label
        self.detail = detail
        self.value = value
    }
}

/// How a series may be drawn. A series declares which of these make sense for it:
/// a share-of-total reads well as a pie, a time series never does.
enum ExplorableChartStyle: String, CaseIterable, Identifiable, Sendable {
    case line = "Line"
    case bar = "Bar"
    case area = "Area"
    case pie = "Pie"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .line: "chart.xyaxis.line"
        case .bar: "chart.bar.fill"
        case .area: "chart.line.uptrend.xyaxis"
        case .pie: "chart.pie.fill"
        }
    }
}

/// Everything the explorer needs to draw, scrub and tabulate a series.
///
/// Points are plotted against their index rather than a date or a category, so a
/// single code path serves time series and categorical breakdowns alike — and the
/// pivot maths becomes a rounding, which keeps scrubbing exact instead of
/// approximate.
struct ExplorableChart: Equatable, Sendable {
    let title: String
    var subtitle: String?
    let xLabel: String
    let yLabel: String
    /// Appended to values in the readout and the table. Empty for a count.
    var unit: String = ""
    /// Digits after the decimal point in every rendered value.
    var fractionDigits: Int = 1
    let points: [ExplorableChartPoint]
    var styles: [ExplorableChartStyle] = [.bar, .line, .area]
    var tint: Color = TessalyticsTheme.accent
    /// Whether the value axis has to include zero. A distance or an energy is
    /// read against zero; a pack capacity or a temperature is not, and anchoring
    /// those flattens the series into a line at the top of the plot.
    var baseline: ChartBaseline = .zero
    /// Whether adding the values up means anything.
    ///
    /// Summing distances gives a mileage. Summing pack capacities gives a number
    /// with no physical meaning, so those series report their latest reading and
    /// their spread instead of a total.
    var isCumulative = true

    static func == (lhs: ExplorableChart, rhs: ExplorableChart) -> Bool {
        lhs.title == rhs.title && lhs.points == rhs.points && lhs.yLabel == rhs.yLabel
    }

    var total: Double { points.map(\.value).reduce(0, +) }
    var mean: Double? { points.isEmpty ? nil : total / Double(points.count) }
    var lowest: ExplorableChartPoint? { points.min { $0.value < $1.value } }
    var highest: ExplorableChartPoint? { points.max { $0.value < $1.value } }

    func formatted(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// A chart the owner can scrub, re-draw and read as a table.
///
/// The point is to let someone answer a question the summary card does not: which
/// day was the outlier, what exactly did that bar total, and does the same data
/// tell a different story as a share rather than a sequence.
struct ChartExplorerView: View {
    let chart: ExplorableChart

    @State private var style: ExplorableChartStyle?
    @State private var selection: Int?

    private var activeStyle: ExplorableChartStyle {
        style ?? chart.styles.first ?? .bar
    }

    private var selectedPoint: ExplorableChartPoint? {
        selection.flatMap { index in chart.points.first { $0.id == index } }
    }

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                    if chart.points.isEmpty {
                        EmptyState(
                            title: "Nothing to plot",
                            message: "This chart has no synchronized values yet.",
                            symbol: "chart.bar.xaxis"
                        )
                    } else {
                        if chart.styles.count > 1 {
                            stylePicker
                        }
                        plotCard
                        summaryCard
                        tableCard
                    }
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth(TessalyticsLayout.wideReadableWidth)
            }
        }
        .navigationTitle(chart.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stylePicker: some View {
        Picker("Presentation", selection: Binding(get: { activeStyle }, set: { style = $0; selection = nil })) {
            ForEach(chart.styles) { option in
                Label(option.rawValue, systemImage: option.symbol).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("chart-style-picker")
    }

    private var plotCard: some View {
        SectionCard(chart.title, subtitle: readoutSubtitle, symbol: activeStyle.symbol, tint: chart.tint) {
            if activeStyle == .pie {
                pieChart
            } else {
                scrubbableChart
                clearReadingButton
            }
        }
    }

    /// The value under the finger, or the series summary when nothing is held.
    private var readoutSubtitle: String {
        if let selectedPoint {
            return "\(selectedPoint.detail ?? selectedPoint.label) · \(chart.formatted(selectedPoint.value))"
        }
        return chart.subtitle ?? "Touch and hold to read values"
    }

    /// Places the readout beside the pivot, nudged to stay inside the plot.
    @ViewBuilder
    private func calloutOverlay(point: ExplorableChartPoint, proxy: ChartProxy, plot: CGRect) -> some View {
        let x = proxy.position(forX: point.id) ?? 0
        let y = proxy.position(forY: point.value) ?? 0
        ScrubCallout(
            title: point.detail ?? point.label,
            value: chart.formatted(point.value),
            tint: chart.tint
        )
        .fixedSize()
        .alignmentGuide(.leading) { dimension in
            // Flip to the other side of the rule when the callout would run off
            // the right-hand edge.
            let wantsLeft = x + 12 + dimension.width > plot.width
            return wantsLeft ? dimension.width + 12 : -12
        }
        .offset(x: plot.minX + x, y: max(plot.minY + y - 46, plot.minY + 2))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var clearReadingButton: some View {
        if selection != nil {
            Button("Clear reading") { selection = nil }
                .font(.caption)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chart-clear-reading")
        }
    }

    private var scrubbableChart: some View {
        Chart(chart.points) { point in
            seriesMark(for: point)
            pivotMarks(for: point)
        }
        .chartXScale(domain: -0.5...(Double(chart.points.count) - 0.5))
        .chartValueDomain(chart.baseline == .focused ? focusedChartDomain(for: chart.points.map(\.value)) : nil)
        .chartXAxis {
            AxisMarks(values: axisIndices) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let index = value.as(Int.self), let point = chart.points.first(where: { $0.id == index }) {
                        Text(point.label).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.precision(.fractionLength(0...chart.fractionDigits))))
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .tessalyticsChartAxes(x: chart.xLabel, y: chart.yLabel)
        .tessalyticsChartStyle()
        .frame(height: 280)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        .gesture(scrubGesture(proxy: proxy, geometry: geometry))
                    if let selectedPoint, let plotFrame = proxy.plotFrame {
                        calloutOverlay(point: selectedPoint, proxy: proxy, plot: geometry[plotFrame])
                    }
                }
            }
        }
        .accessibilityIdentifier("chart-explorer-plot")
    }

    @ChartContentBuilder
    private func seriesMark(for point: ExplorableChartPoint) -> some ChartContent {
        switch activeStyle {
        case .bar:
            BarMark(
                x: .value(chart.xLabel, point.id),
                y: .value(chart.yLabel, point.value)
            )
            .foregroundStyle(chart.tint.opacity(selection == nil || selection == point.id ? 1 : 0.35))
            .clipShape(.rect(cornerRadius: 3))
        case .area:
            AreaMark(
                x: .value(chart.xLabel, point.id),
                y: .value(chart.yLabel, point.value),
                stacking: .unstacked
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(colors: [chart.tint.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
            LineMark(
                x: .value(chart.xLabel, point.id),
                y: .value(chart.yLabel, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(chart.tint)
        case .line, .pie:
            LineMark(
                x: .value(chart.xLabel, point.id),
                y: .value(chart.yLabel, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(chart.tint)
        }
    }

    /// The pivot: a full-height rule plus a dot and its readout, so the value is
    /// unambiguous even where the line is flat.
    @ChartContentBuilder
    private func pivotMarks(for point: ExplorableChartPoint) -> some ChartContent {
        if let selectedPoint, selectedPoint.id == point.id {
            RuleMark(x: .value(chart.xLabel, selectedPoint.id))
                .foregroundStyle(TessalyticsTheme.steel.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            PointMark(
                x: .value(chart.xLabel, selectedPoint.id),
                y: .value(chart.yLabel, selectedPoint.value)
            )
            .foregroundStyle(chart.tint)
            .symbolSize(90)
        }
    }

    /// Touch and hold, then slide: a drag with no minimum distance, so a plain
    /// press reads a value immediately.
    ///
    /// The reading survives the lift. Clearing on release is the usual gesture,
    /// but it means the value can never be studied — the finger is covering the
    /// callout right up until the moment it disappears.
    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard let plotFrame = proxy.plotFrame else { return }
                let origin = geometry[plotFrame].origin
                let x = drag.location.x - origin.x
                guard let position: Double = proxy.value(atX: x) else { return }
                let index = Int(position.rounded())
                guard chart.points.indices.contains(index) else { return }
                if selection != index {
                    selection = index
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
            }
    }

    /// At most eight labels, so they never overlap on a phone.
    private var axisIndices: [Int] {
        let count = chart.points.count
        guard count > 8 else { return chart.points.map(\.id) }
        let stride = max(count / 6, 1)
        return chart.points.map(\.id).enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }

    private var pieChart: some View {
        VStack(spacing: 10) {
            Chart(pieSlices) { slice in
                SectorMark(
                    angle: .value(chart.yLabel, slice.value),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value(chart.xLabel, slice.label))
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 260)
            .accessibilityIdentifier("chart-explorer-pie")

            Text("Share of \(chart.formatted(chart.total))")
                .accessibilityIdentifier("chart-explorer-pie-total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Pies stop being readable past a handful of wedges, so the smallest values
    /// are collected rather than drawn as slivers.
    private var pieSlices: [ExplorableChartPoint] {
        let positive = chart.points.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard positive.count > 7 else { return positive }
        let leading = positive.prefix(6)
        let rest = positive.dropFirst(6)
        return Array(leading) + [
            ExplorableChartPoint(
                id: -1,
                label: "Other (\(rest.count))",
                value: rest.map(\.value).reduce(0, +)
            )
        ]
    }

    private var summaryCard: some View {
        SectionCard("Summary", symbol: "sum", tint: TessalyticsTheme.neutral) {
            MetricGrid {
                if chart.isCumulative {
                    MetricCard(
                        title: "Total",
                        value: chart.formatted(chart.total),
                        symbol: "plus.forwardslash.minus",
                        tint: chart.tint
                    )
                } else if let latest = chart.points.last {
                    MetricCard(
                        title: "Latest",
                        value: chart.formatted(latest.value),
                        symbol: "clock.arrow.circlepath",
                        detail: latest.label,
                        tint: chart.tint
                    )
                }
                if let mean = chart.mean {
                    MetricCard(
                        title: "Average",
                        value: chart.formatted(mean),
                        symbol: "chart.bar.xaxis",
                        tint: chart.tint
                    )
                }
                if let highest = chart.highest {
                    MetricCard(
                        title: "Highest",
                        value: chart.formatted(highest.value),
                        symbol: "arrow.up.right",
                        detail: highest.label,
                        tint: TessalyticsTheme.warning
                    )
                }
                if let lowest = chart.lowest {
                    MetricCard(
                        title: "Lowest",
                        value: chart.formatted(lowest.value),
                        symbol: "arrow.down.right",
                        detail: lowest.label,
                        tint: TessalyticsTheme.steel
                    )
                }
            }
        }
    }

    private var tableCard: some View {
        SectionCard("Values", subtitle: "\(chart.points.count) rows", symbol: "tablecells", tint: TessalyticsTheme.neutral) {
            VStack(spacing: 0) {
                ForEach(chart.points.reversed()) { point in
                    if point.id != chart.points.last?.id { Divider() }
                    HStack {
                        Text(point.detail ?? point.label)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(chart.formatted(point.value))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                }
            }
            .accessibilityIdentifier("chart-explorer-table")
        }
    }
}

/// The floating readout attached to the scrubbed point.
private struct ScrubCallout: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: .rect(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .fixedSize()
    }
}
