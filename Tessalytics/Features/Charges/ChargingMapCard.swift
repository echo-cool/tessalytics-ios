import MapKit
import SwiftUI

/// Where charging energy actually goes, weighted by kilowatt-hours.
///
/// The Grafana equivalent is a heat map keyed on geofence name falling back to a
/// composed street address. TeslaMateApi already resolves an address per charge
/// and returns its coordinates, so sessions are grouped by that address and each
/// site is drawn proportional to the energy delivered there — a marker per
/// session would say only where the car stopped, not where the electricity came
/// from.
struct ChargingMapCard: View {
    let sites: [ChargingSite]

    @Environment(\.colorScheme) private var colorScheme
    @State private var position: MapCameraPosition = .automatic

    private var totalEnergy: Double { sites.map(\.energyAdded).reduce(0, +) }

    var body: some View {
        SectionCard(
            "Charging by location",
            subtitle: sites.isEmpty
                ? "No positioned charging sessions yet"
                : "\(sites.count) site\(sites.count == 1 ? "" : "s") · \(ValueFormatting.energy(totalEnergy)) added",
            symbol: "map.circle.fill",
            tint: TessalyticsTheme.positive
        ) {
            if sites.isEmpty {
                ChartNeedsMoreHistory(
                    needs: "a charging session that reports coordinates",
                    symbol: "map"
                )
            } else {
                Map(position: $position, interactionModes: [.pan, .zoom]) {
                    ForEach(sites) { site in
                        Annotation(site.name, coordinate: site.coordinate) {
                            SiteBubble(site: site)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TessalyticsTheme.hairline(for: colorScheme), lineWidth: 1)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Map of charging locations, sized by energy delivered")
                .accessibilityIdentifier("charging-map")
                // `.automatic` only frames the annotations it knows about at
                // first layout, so re-fit whenever the site set changes.
                .task(id: sites.map(\.id).joined()) { position = .automatic }

                ChartLegend("Bubble size = energy added (kWh)", color: TessalyticsTheme.positive)

                VStack(spacing: 6) {
                    ForEach(sites.prefix(5)) { site in
                        SiteRow(site: site)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private extension ChargingSite {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Proportional bubble. Area scales with energy share so the visual weight
/// matches the number rather than exaggerating it.
private struct SiteBubble: View {
    let site: ChargingSite

    private var diameter: CGFloat {
        let scaled = sqrt(max(site.share, 0.005)) * 78
        return min(max(scaled, 16), 62)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(TessalyticsTheme.positive.opacity(0.28))
            Circle()
                .strokeBorder(TessalyticsTheme.positive, lineWidth: 1.5)
            if diameter >= 30 {
                Text(site.share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TessalyticsTheme.positive)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(site.name)
        .accessibilityValue(
            "\(ValueFormatting.energy(site.energyAdded)), \(ValueFormatting.percentage(site.share, digits: 0)) of all charging"
        )
    }
}

private struct SiteRow: View {
    let site: ChargingSite

    var body: some View {
        HStack(spacing: 10) {
            Text(site.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(site.sessions)×")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(ValueFormatting.energy(site.energyAdded))
                .font(.caption.weight(.medium).monospacedDigit())
            Text(ValueFormatting.percentage(site.share, digits: 0))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(TessalyticsTheme.positive)
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(site.name)
        .accessibilityValue(
            "\(site.sessions) sessions, \(ValueFormatting.energy(site.energyAdded)), \(ValueFormatting.percentage(site.share, digits: 0))"
        )
    }
}
