import SwiftData
import SwiftUI

struct ChargeHistoryView: View {
    var embedded = false
    var title: String?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var records: [ChargeRecord] = []
    @State private var loading = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var message: String?
    @State private var currentCharge: ChargeDetailDTO?
    @State private var selectedCharge: ChargeSelection?

    var body: some View {
        if embedded {
            historyContent
        } else {
            NavigationStack { historyContent }
        }
    }

    private var historyContent: some View {
        TessalyticsScreen(showsTopAccent: !embedded) {
            Group {
                if records.isEmpty && loading {
                    LoadingPanel(title: "Synchronizing charging sessions", symbol: "bolt.car")
                        .padding()
                } else if records.isEmpty {
                    EmptyState(title: "No charging sessions", message: message ?? "Completed sessions appear once your server has recorded them.", symbol: "bolt.car")
                } else {
                    list
                }
            }
        }
        .navigationTitle(title ?? (embedded ? "Activity" : "Charging"))
        .safeAreaInset(edge: .top) { if environment.isOffline { OfflineBanner() } }
        .navigationDestination(item: $selectedCharge) { selection in
            ChargeDetailView(chargeID: selection.id)
        }
        .task(id: environment.selectedVehicle?.id) {
            loadCached()
            if !environment.isDemoMode {
                await loadCurrent()
                if records.isEmpty { await refresh() }
            }
        }
        .accessibilityIdentifier("charge-history-screen")
    }

    private var list: some View {
        List {
            if let currentCharge {
                Section {
                    Button { selectedCharge = ChargeSelection(id: currentCharge.chargeId) } label: {
                        SurfaceCard(tint: TessalyticsTheme.positive) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(TessalyticsTheme.positive)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Charging now")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(ValueFormatting.number(currentCharge.chargeEnergyAdded, unit: "kWh")) added")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(records, id: \.chargeID) { record in
                Button { selectedCharge = ChargeSelection(id: record.chargeID) } label: { ChargeRow(record: record) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("charge-card-\(record.chargeID)")
                    .onAppear {
                        if !environment.isDemoMode, record.chargeID == records.last?.chargeID {
                            Task { await loadMore() }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Attached to the List itself, and awaiting the fetch, so the control
        // finishes exactly when the data does.
        .refreshable {
            await refresh()
            await loadCurrent()
        }
    }
    private func loadCached() { guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }; records = ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id) }
    private func refresh() async {
        guard !environment.isDemoMode else { return }
        page = 1; hasMore = true; await fetch(page: 1)
    }
    private func loadMore() async { guard hasMore, !loading else { return }; page += 1; await fetch(page: page) }
    private func fetch(page: Int) async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        loading = true; defer { loading = false }
        do { let before = records.count; records = try await ChargeRepository(context: context).refresh(client: environment.client(for: profile), serverID: profile.id, carID: vehicle.id, page: page, filter: .init()); hasMore = records.count > before || page == 1; message = nil }
        catch { loadCached(); message = error.localizedDescription }
    }
    private func loadCurrent() async {
        // Demo mode has no reachable server; skip the pointless request.
        guard !environment.isDemoMode,
              let profile = environment.selectedProfile,
              let vehicle = environment.selectedVehicle else { return }
        currentCharge = try? await environment.client(for: profile).currentCharge(carID: vehicle.id).charge
    }
}

/// Charging session row.
///
/// Energy added is the headline figure because it is the one value TeslaMate
/// reports for every session. Cost appears only when the server actually has a
/// price configured — a column of "$0.00" tells the owner nothing.
private struct ChargeSelection: Identifiable, Hashable {
    let id: Int
}

private struct ChargeRow: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context

    let record: ChargeRecord

    @State private var curve: [ChargeCurvePoint] = []

    /// A cost of zero means "no tariff configured", not "this charge was free".
    private var reportedCost: Double? { (record.cost ?? 0) > 0 ? record.cost : nil }

    private var averagePower: String? {
        guard let energy = record.energyAdded, energy > 0,
              let minutes = record.durationMinutes, minutes > 0 else { return nil }
        let kilowatts = energy / (Double(minutes) / 60)
        return ValueFormatting.number(kilowatts, unit: "kW", digits: kilowatts < 10 ? 1 : 0)
    }

    private var facts: [String] {
        [
            averagePower.map { "\($0) avg" },
            record.durationMinutes.map { _ in ValueFormatting.duration(minutes: record.durationMinutes) },
            reportedCost.map { ValueFormatting.currency($0) }
        ].compactMap { $0 }
    }

    var body: some View {
        SurfaceCard(tint: TessalyticsTheme.positive) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(ValueFormatting.date(record.startDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if record.endDate == nil {
                            StatusBadge(text: "Charging", color: TessalyticsTheme.positive)
                        }
                    }

                    Text(ValueFormatting.number(record.energyAdded, unit: "kWh"))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Label(record.address ?? "Location not reported", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary, TessalyticsTheme.positive)
                        .lineLimit(2)

                    if !facts.isEmpty {
                        Text(facts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Fetched per row the way a drive row fetches its route, and
                // cached the same way, so scrolling does not re-request.
                if curve.count > 2 {
                    ChargeCurveChart(points: curve, height: 56, isCompact: true)
                        .frame(width: 104)
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .task(id: record.chargeID) { await loadCurve() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.address ?? "Charging session")
        .accessibilityValue(
            ([ValueFormatting.date(record.startDate), ValueFormatting.number(record.energyAdded, unit: "kWh")] + facts)
                .joined(separator: ", ")
        )
    }

    private func loadCurve() async {
        guard curve.isEmpty,
              let profile = environment.selectedProfile,
              let vehicle = environment.selectedVehicle else { return }
        guard let detail = try? await ChargeRepository(context: context).detail(
            client: environment.client(for: profile),
            serverID: profile.id,
            carID: vehicle.id,
            chargeID: record.chargeID
        ) else { return }
        // Coarse for a thumbnail: the shape survives, the work does not.
        curve = detail.curvePoints(limit: 40)
    }
}
