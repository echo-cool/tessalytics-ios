import SwiftData
import SwiftUI

struct ChargeHistoryView: View {
    var embedded = false

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var records: [ChargeRecord] = []
    @State private var loading = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var message: String?
    @State private var currentCharge: ChargeDetailDTO?

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
                    EmptyState(title: "No charging sessions", message: message ?? "Completed sessions will appear after TeslaMateApi reports them.", symbol: "bolt.car")
                } else {
                    list
                }
            }
        }
        .navigationTitle(embedded ? "Activity" : "Charging")
        .safeAreaInset(edge: .top) { if environment.isOffline { OfflineBanner() } }
        .task(id: environment.selectedVehicle?.id) { loadCached(); await loadCurrent(); if records.isEmpty { await refresh() } }
        .refreshable { await refresh() }
        .accessibilityIdentifier("charge-history-screen")
    }

    private var list: some View {
        List {
            if let currentCharge {
                Section {
                    NavigationLink { ChargeDetailView(chargeID: currentCharge.chargeId) } label: {
                        SurfaceCard(tint: TessalyticsTheme.positive) {
                            Label("Charging now — \(ValueFormatting.number(currentCharge.chargeEnergyAdded, unit: "kWh")) added", systemImage: "bolt.circle.fill")
                                .font(.headline)
                                .foregroundStyle(TessalyticsTheme.positive)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(records, id: \.chargeID) { record in
                NavigationLink { ChargeDetailView(chargeID: record.chargeID) } label: { ChargeRow(record: record) }
                    .onAppear { if record.chargeID == records.last?.chargeID { Task { await loadMore() } } }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    private func loadCached() { guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }; records = ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id) }
    private func refresh() async { page = 1; hasMore = true; await fetch(page: 1) }
    private func loadMore() async { guard hasMore, !loading else { return }; page += 1; await fetch(page: page) }
    private func fetch(page: Int) async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        loading = true; defer { loading = false }
        do { let before = records.count; records = try await ChargeRepository(context: context).refresh(client: environment.client(for: profile), serverID: profile.id, carID: vehicle.id, page: page, filter: .init()); hasMore = records.count > before || page == 1; message = nil }
        catch { loadCached(); message = error.localizedDescription }
    }
    private func loadCurrent() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        currentCharge = try? await environment.client(for: profile).currentCharge(carID: vehicle.id).charge
    }
}

private struct ChargeRow: View {
    let record: ChargeRecord
    var body: some View {
        SurfaceCard(tint: TessalyticsTheme.positive) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ValueFormatting.date(record.startDate)).font(.headline)
                    Spacer()
                    if record.endDate == nil { StatusBadge(text: "Charging", color: TessalyticsTheme.positive) }
                }
                Label(record.address ?? "Location not reported", systemImage: "mappin.and.ellipse")
                    .lineLimit(1)
                HStack {
                    Label(ValueFormatting.number(record.energyAdded, unit: "kWh"), systemImage: "bolt.fill")
                    Spacer()
                    Text(ValueFormatting.currency(record.cost))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
