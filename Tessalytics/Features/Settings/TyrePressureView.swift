import SwiftUI

/// The four corners, at a size worth reading.
///
/// The hero card draws the same diagram at 84 points, which is enough to notice
/// that something is amber and not enough to act on. This is where the reading
/// actually is: the pressure, whether the car has flagged it, and how old the
/// reading is — because a sleeping car reports nothing at all, and a pressure
/// from three days ago is a different fact from a pressure from a minute ago.
struct TyrePressureView: View {
    @Environment(AppEnvironment.self) private var environment

    /// A sleeping car reports 0 psi at every corner, so fall back to the last
    /// reading taken while it was awake — the same rule the hero card uses.
    private var pressures: TPMSDTO? {
        environment.status?.tpmsDetails?.hasAnyReading == true
            ? environment.status?.tpmsDetails
            : environment.lastLiveStatus?.tpmsDetails
    }

    private var isLive: Bool { environment.status?.tpmsDetails?.hasAnyReading == true }
    private var units: UnitsDTO { environment.statusUnits ?? .metricDefaults }
    private var readAt: Date? { isLive ? environment.statusFetchedAt : environment.lastLiveStatusAt }

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                VStack(spacing: TessalyticsLayout.stackSpacing) {
                    pageContent
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth()
            }
        }
        .navigationTitle("Tyres")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tyre-pressure-screen")
        .shareablePage(sharePage) {
            VStack(spacing: TessalyticsLayout.stackSpacing) { pageContent }
        }
    }

    @ViewBuilder private var pageContent: some View {
        if pressures?.hasAnyReading == true {
            diagram
            corners
            freshness
        } else {
            EmptyState(
                title: "No tyre readings",
                message: "No tyre pressure reported yet. TeslaMate reads these while the car is awake.",
                symbol: "gauge.with.dots.needle.bottom.50percent"
            )
        }
    }

    private func sharePage() -> SharePage {
        let readings: [(String, Double?)] = [
            ("front left", pressures?.tpmsPressureFl),
            ("front right", pressures?.tpmsPressureFr),
            ("rear left", pressures?.tpmsPressureRl),
            ("rear right", pressures?.tpmsPressureRr)
        ]
        let highlights = readings.compactMap { label, value -> ShareHighlight? in
            guard let value else { return nil }
            return ShareHighlight(label: label, value: ValueFormatting.pressure(value, units: units, digits: 1))
        }

        var sentences = ["Tyre pressures for \(environment.selectedVehicle?.name?.nilIfEmpty ?? "my Tesla")."]
        if let readAt {
            // A tyre pressure is only as good as the moment it was read: the car
            // stops reporting the moment it sleeps.
            sentences.append("Read \(ValueFormatting.readingTime(readAt)).")
        }
        return SharePage(
            title: "Tyres",
            subtitle: SharePage.subtitle(car: environment.selectedVehicle?.name),
            highlights: highlights,
            summary: sentences.joined(separator: " ")
        )
    }

    private var diagram: some View {
        SectionCard(
            "Pressures",
            subtitle: pressures?.hasAnyWarning == true ? "The car has flagged a soft tyre" : "As the car last reported them",
            symbol: "car.top.door.front.left.and.front.right.and.rear.left.and.rear.right.open",
            tint: pressures?.hasAnyWarning == true ? TessalyticsTheme.warning : TessalyticsTheme.neutral
        ) {
            TirePressureDiagram(pressures: pressures, units: environment.statusUnits, height: 200)
                .frame(maxWidth: .infinity)
        }
    }

    private var corners: some View {
        SectionCard("Each corner", symbol: "list.bullet", tint: TessalyticsTheme.neutral) {
            MetricGrid {
                ForEach(TyreCorner.allCases) { corner in
                    MetricCard(
                        title: corner.title,
                        value: corner.pressure(pressures).map {
                            ValueFormatting.number($0, unit: units.pressureSymbol, digits: 1)
                        } ?? "No reading",
                        symbol: corner.warns(pressures) ? "exclamationmark.triangle.fill" : "circle.dashed",
                        detail: corner.detail(pressures),
                        tint: corner.warns(pressures) ? TessalyticsTheme.warning : TessalyticsTheme.steel
                    )
                    .accessibilityIdentifier("tyre-corner-\(corner.rawValue)")
                }
            }
        }
    }

    private var freshness: some View {
        SectionCard("Reading", symbol: "clock", tint: TessalyticsTheme.steel) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Source", value: isLive ? "The car, awake" : "Last reading while awake")
                if let readAt {
                    LabeledContent("Taken", value: ValueFormatting.date(readAt))
                }
                Text(
                    isLive
                        ? "Read from the car. Pressures fall as the tyres cool."
                        : "The car is asleep, so this is the last reading taken while it was awake."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One wheel, and the two readings the car gives for it.
enum TyreCorner: String, CaseIterable, Identifiable {
    case frontLeft, frontRight, rearLeft, rearRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontLeft: "Front left"
        case .frontRight: "Front right"
        case .rearLeft: "Rear left"
        case .rearRight: "Rear right"
        }
    }

    func pressure(_ tyres: TPMSDTO?) -> Double? {
        switch self {
        case .frontLeft: TPMSDTO.reported(tyres?.tpmsPressureFl)
        case .frontRight: TPMSDTO.reported(tyres?.tpmsPressureFr)
        case .rearLeft: TPMSDTO.reported(tyres?.tpmsPressureRl)
        case .rearRight: TPMSDTO.reported(tyres?.tpmsPressureRr)
        }
    }

    /// The car's own soft-pressure flag, when it reports one.
    func warning(_ tyres: TPMSDTO?) -> Bool? {
        switch self {
        case .frontLeft: tyres?.tpmsWarningFl
        case .frontRight: tyres?.tpmsWarningFr
        case .rearLeft: tyres?.tpmsWarningRl
        case .rearRight: tyres?.tpmsWarningRr
        }
    }

    func warns(_ tyres: TPMSDTO?) -> Bool { warning(tyres) == true }

    /// What the car said about this corner, distinguishing "fine" from "unknown".
    func detail(_ tyres: TPMSDTO?) -> String {
        switch warning(tyres) {
        case true: "The car flagged this one"
        case false: "No warning"
        default: pressure(tyres) == nil ? "No sensor reading" : "The car did not say"
        }
    }
}
