import Charts
import SwiftData
import SwiftUI

struct SoftwareUpdatesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var updates: [FirmwareUpdateDTO] = []
    @State private var loading = true
    @State private var message: String?

    /// Newest first, which is the order the list reads in.
    private var periods: [SoftwareVersionPeriod] { SoftwareTimeline.periods(from: updates) }

    var body: some View {
        TessalyticsScreen {
            Group {
                if loading {
                    LoadingPanel(title: "Loading update history", symbol: "arrow.triangle.2.circlepath")
                        .padding()
                } else if periods.isEmpty {
                    EmptyState(
                        title: "No update history",
                        message: message ?? "No software updates have been reported.",
                        symbol: "arrow.triangle.2.circlepath"
                    )
                } else {
                    content
                }
            }
        }
        .navigationTitle("Software updates")
        .tessalyticsReadableWidth()
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                SectionCard(
                    "Version timeline",
                    subtitle: timelineSubtitle,
                    symbol: "chart.bar.xaxis",
                    tint: TessalyticsTheme.accent
                ) {
                    SoftwareVersionTimelineChart(periods: periods)
                }

                ForEach(periods) { period in
                    SoftwareVersionRow(period: period)
                }
            }
            .tessalyticsScreenPadding()
            .tessalyticsReadableWidth()
        }
    }

    private var timelineSubtitle: String {
        let count = periods.count
        let tracked = periods.map { $0.days() }.reduce(0, +)
        return "\(count) version\(count == 1 ? "" : "s") · \(tracked) day\(tracked == 1 ? "" : "s") recorded"
    }

    private func load() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else {
            loading = false
            return
        }
        if environment.isDemoMode {
            loadCached(profile: profile, vehicle: vehicle)
            loading = false
            return
        }
        do {
            // The API does not guarantee an order; the cached path sorts newest
            // first, so the live path must match or the list reshuffles.
            updates = try await environment.client(for: profile).updates(carID: vehicle.id).updates
                .sorted { ($0.endDate?.value ?? $0.startDate?.value ?? .distantPast) > ($1.endDate?.value ?? $1.startDate?.value ?? .distantPast) }
            for dto in updates {
                let key = "\(profile.id.uuidString):\(vehicle.id):update:\(dto.updateId)"
                let descriptor = FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.cacheKey == key })
                if try context.fetch(descriptor).isEmpty {
                    context.insert(FirmwareUpdateRecord(serverID: profile.id, carID: vehicle.id, dto: dto))
                }
            }
            try context.save()
            message = nil
        } catch {
            loadCached(profile: profile, vehicle: vehicle)
            message = error.localizedDescription
        }
        loading = false
    }

    private func loadCached(profile: ServerProfile, vehicle: Vehicle) {
        let server = profile.id.uuidString
        let car = vehicle.id
        let descriptor = FetchDescriptor<FirmwareUpdateRecord>(
            predicate: #Predicate { $0.serverID == server && $0.carID == car },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        updates = cached.map {
            FirmwareUpdateDTO(
                updateId: $0.updateID,
                startDate: FlexibleDate($0.startDate),
                endDate: FlexibleDate($0.endDate),
                version: $0.version
            )
        }
    }
}

/// Which version was running when.
///
/// A bar per version rather than one stacked band: a stacked band needs a legend
/// to say which colour is which, and a legend of a dozen firmware numbers is
/// harder to read than the chart it explains. One row per version puts the name
/// beside its own bar.
struct SoftwareVersionTimelineChart: View {
    let periods: [SoftwareVersionPeriod]
    /// How many versions the chart draws before it starts leaving the oldest off.
    ///
    /// A car with four years of updates has thirty of them, and thirty rows is a
    /// scroll rather than a chart. The list underneath still has all of them.
    static let maximumRows = 12

    private var drawn: [SoftwareVersionPeriod] { Array(periods.prefix(Self.maximumRows)) }
    /// Oldest at the bottom, which is how a timeline reads.
    private var chronological: [SoftwareVersionPeriod] { drawn.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(chronological) { period in
                BarMark(
                    xStart: .value("Installed", period.installedAt),
                    xEnd: .value("Replaced", period.end()),
                    y: .value("Version", period.version)
                )
                .foregroundStyle(period.isCurrent ? TessalyticsTheme.accentBright : TessalyticsTheme.chartNeutral)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { value in
                    AxisValueLabel {
                        if let version = value.as(String.self) {
                            Text(version)
                                .font(.caption2.monospacedDigit())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.caption2)
                }
            }
            // Ordered explicitly: without this the y axis sorts the versions as
            // text, and "2026.20.3" sorts above "2026.8.1".
            .chartYScale(domain: chronological.map(\.version))
            .frame(height: max(120, CGFloat(chronological.count) * 26 + 34))
            .accessibilityLabel("Which software version the car ran, over time")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("software-version-timeline")

            HStack(spacing: 14) {
                ChartLegend("Running now", color: TessalyticsTheme.accentBright)
                ChartLegend("Superseded", color: TessalyticsTheme.chartNeutral)
            }

            if periods.count > Self.maximumRows {
                Text("Showing the \(Self.maximumRows) most recent versions. The full history is listed below.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityValue: String {
        chronological
            .map { "\($0.version) for \($0.durationDescription())" }
            .joined(separator: ", ")
    }
}

/// One version, and how long the car ran it.
private struct SoftwareVersionRow: View {
    let period: SoftwareVersionPeriod

    var body: some View {
        SurfaceCard(tint: period.isCurrent ? TessalyticsTheme.accent : TessalyticsTheme.neutral) {
            HStack(spacing: 14) {
                Image(systemName: period.isCurrent ? "checkmark.seal.fill" : "shippingbox.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(period.isCurrent ? TessalyticsTheme.positive : TessalyticsTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        (period.isCurrent ? TessalyticsTheme.positive : TessalyticsTheme.accent).opacity(0.10),
                        in: .rect(cornerRadius: 11)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(period.version)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if period.isCurrent {
                            StatusBadge(text: "Current", color: TessalyticsTheme.positive)
                        }
                    }
                    Text(ValueFormatting.date(period.installedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(period.days().formatted())
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(period.days() == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(period.version)
        .accessibilityValue(
            "Installed \(ValueFormatting.date(period.installedAt)), \(period.durationDescription())"
        )
        .accessibilityIdentifier("software-version-row")
    }
}
