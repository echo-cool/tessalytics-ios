import SwiftData
import SwiftUI

struct DriveHistoryView: View {
    var embedded = false

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
                    EmptyState(title: "No drives", message: message ?? "Completed drives will appear after TeslaMateApi reports them.", symbol: "road.lanes")
                } else {
                    list
                }
            }
        }
        .navigationTitle(embedded ? "Activity" : "Drives")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Filter drives", systemImage: "line.3.horizontal.decrease.circle") { showFilters.toggle() }
                    .labelStyle(.iconOnly)
            }
        }
        .safeAreaInset(edge: .top) { if environment.isOffline { OfflineBanner() } }
        .sheet(isPresented: $showFilters) { filterSheet }
        .task(id: environment.selectedVehicle?.id) { loadCached(); if records.isEmpty { await refresh() } }
        .refreshable { await refresh() }
        .accessibilityIdentifier("drive-history-screen")
    }

    private var list: some View {
        List {
            ForEach(records, id: \.driveID) { record in
                NavigationLink { DriveDetailView(driveID: record.driveID) } label: { DriveRow(record: record) }
                    .onAppear { if record.driveID == records.last?.driveID { Task { await loadMore() } } }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            if !hasMore { Text("All synchronized drives loaded").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
    let record: DriveRecord
    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ValueFormatting.date(record.startDate)).font(.headline)
                    Spacer()
                    if record.endDate == nil { StatusBadge(text: "In progress", color: TessalyticsTheme.accent) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label(record.startAddress ?? "Start not reported", systemImage: "circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary, TessalyticsTheme.positive)
                        .lineLimit(1)
                    Label(record.endAddress ?? "End not reported", systemImage: "mappin.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary, TessalyticsTheme.critical)
                        .lineLimit(1)
                }
                HStack {
                    Label(ValueFormatting.number(record.distance, unit: ""), systemImage: "arrow.left.and.right")
                    Spacer()
                    Label(ValueFormatting.duration(minutes: record.durationMinutes), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
