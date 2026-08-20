import MapKit
import SwiftData
import SwiftUI

struct DriveHistoryView: View {
    var embedded = false
    var title: String?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var records: [DriveRecord] = []
    @State private var loading = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var location = ""
    @State private var showFilters = false
    @State private var usesStartDate = false
    @State private var usesEndDate = false
    @State private var startDate = Date.now.addingTimeInterval(-30 * 86_400)
    @State private var endDate = Date.now
    @State private var minimumDistance = ""
    @State private var maximumDistance = ""
    @State private var message: String?
    @State private var selectedDrive: DriveSelection?

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
                    LoadingPanel(title: "Synchronizing drives", symbol: "road.lanes")
                        .padding()
                } else if records.isEmpty {
                    EmptyState(title: "No drives", message: message ?? "Completed drives appear once your server has recorded them.", symbol: "road.lanes")
                } else {
                    list
                }
            }
        }
        .navigationTitle(title ?? (embedded ? "Activity" : "Drives"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Filter drives", systemImage: "line.3.horizontal.decrease.circle") { showFilters.toggle() }
                    .labelStyle(.iconOnly)
            }
        }
        .safeAreaInset(edge: .top) { if environment.isOffline { OfflineBanner() } }
        .sheet(isPresented: $showFilters) { filterSheet }
        .navigationDestination(item: $selectedDrive) { selection in
            DriveDetailView(driveID: selection.id)
        }
        .task(id: environment.selectedVehicle?.id) { loadCached(); if records.isEmpty { await refresh() } }
        .accessibilityIdentifier("drive-history-screen")
    }

    private var list: some View {
        List {
            ForEach(records, id: \.driveID) { record in
                Button { selectedDrive = DriveSelection(id: record.driveID) } label: { DriveRow(record: record) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("drive-card-\(record.driveID)")
                    .onAppear {
                        if !environment.isDemoMode, record.driveID == records.last?.driveID {
                            Task { await loadMore() }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            if !hasMore { Text("All synchronized drives loaded").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Attached to the List itself, and awaiting the fetch, so the control
        // finishes exactly when the data does.
        .refreshable { await refresh() }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    Toggle("Start date", isOn: $usesStartDate)
                    if usesStartDate { DatePicker("From", selection: $startDate, displayedComponents: .date) }
                    Toggle("End date", isOn: $usesEndDate)
                    if usesEndDate { DatePicker("Through", selection: $endDate, displayedComponents: .date) }
                }
                Section("Location") { TextField("Address or geofence", text: $location) }
                Section("Distance") {
                    TextField("Minimum", text: $minimumDistance).keyboardType(.decimalPad)
                    TextField("Maximum", text: $maximumDistance).keyboardType(.decimalPad)
                }
            }
                .navigationTitle("Drive filters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showFilters = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { showFilters = false; Task { await refresh() } } }
                }
        }.presentationDetents([.medium])
    }

    private func loadCached() {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        records = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
    }
    private func refresh() async {
        guard !environment.isDemoMode else { return }
        page = 1; hasMore = true
        await fetch(page: page, replace: true)
    }
    private func loadMore() async { guard hasMore, !loading else { return }; page += 1; await fetch(page: page, replace: false) }
    private func fetch(page: Int, replace: Bool) async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        loading = true; defer { loading = false }
        do {
            let client = try environment.client(for: profile)
            let before = records.count
            records = try await DriveRepository(context: context).refresh(client: client, serverID: profile.id, carID: vehicle.id, page: page,
                                                                           filter: DateRangeFilter(start: usesStartDate ? startDate : nil,
                                                                                                   end: usesEndDate ? endDate : nil,
                                                                                                   location: location.nilIfEmpty,
                                                                                                   minimumDistance: Double(minimumDistance),
                                                                                                   maximumDistance: Double(maximumDistance)))
            hasMore = records.count > before || replace
            message = nil
        } catch { loadCached(); message = error.localizedDescription }
    }
}

private struct DriveRow: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    let record: DriveRecord
    @State private var route: [CoordinateDTO] = []

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(ValueFormatting.date(record.startDate))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    if record.endDate == nil { StatusBadge(text: "In progress", color: TessalyticsTheme.accent) }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                RouteSnapshotView(route: route, driveID: record.driveID, height: 160)
                DriveEndpointRow(
                    start: record.startAddress ?? "Start not reported",
                    end: record.endAddress ?? "End not reported"
                )
                HStack {
                    Label(ValueFormatting.distance(record.distance, units: environment.statusUnits), systemImage: "arrow.left.and.right")
                    Spacer()
                    Label(ValueFormatting.duration(minutes: record.durationMinutes), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .task(id: record.driveID) { await loadRoute() }
        .accessibilityElement(children: .contain)
    }

    private func loadRoute() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        do {
            let detail = try await DriveRepository(context: context).detail(
                client: environment.client(for: profile),
                serverID: profile.id,
                carID: vehicle.id,
                driveID: record.driveID
            )
            route = RouteSimplifier.simplify(detail.driveDetails.map(\.coordinate), tolerance: 0.00025)
        } catch {
            route = []
        }
    }
}

private struct DriveSelection: Identifiable, Hashable {
    let id: Int
}

/// Start and end addresses with correctly tinted markers.
///
/// `Label` with a palette style silently falls back to the primary colour for
/// single-layer symbols like `circle.fill`, which rendered the start pin white.
struct DriveEndpointRow: View {
    let start: String
    let end: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            endpoint(symbol: "circle.fill", tint: TessalyticsTheme.positive, text: start, label: "From")
            endpoint(symbol: "mappin.circle.fill", tint: TessalyticsTheme.critical, text: end, label: "To")
        }
    }

    private func endpoint(symbol: String, tint: Color, text: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }
}
