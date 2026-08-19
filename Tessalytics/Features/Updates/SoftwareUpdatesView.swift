import SwiftUI
import SwiftData

struct SoftwareUpdatesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var updates: [FirmwareUpdateDTO] = []
    @State private var loading = true
    @State private var message: String?
    var body: some View {
        TessalyticsScreen {
            Group {
                if loading {
                    LoadingPanel(title: "Loading update history", symbol: "arrow.triangle.2.circlepath")
                        .padding()
                } else if updates.isEmpty {
                    EmptyState(title: "No update history", message: message ?? "No software updates have been reported.", symbol: "arrow.triangle.2.circlepath")
                } else {
                    List(updates) { update in
                        SurfaceCard(tint: TessalyticsTheme.neutral) {
                            HStack(spacing: 14) {
                                Image(systemName: "shippingbox.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(TessalyticsTheme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(TessalyticsTheme.accent.opacity(0.10), in: .rect(cornerRadius: 11))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(update.version ?? "Version not reported").font(.headline)
                                    Text(ValueFormatting.date(update.endDate?.value ?? update.startDate?.value)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Software updates")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { loading = false; return }
        do {
            updates = try await environment.client(for: profile).updates(carID: vehicle.id).updates
            for dto in updates {
                let key = "\(profile.id.uuidString):\(vehicle.id):update:\(dto.updateId)"
                let descriptor = FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.cacheKey == key })
                if try context.fetch(descriptor).isEmpty { context.insert(FirmwareUpdateRecord(serverID: profile.id, carID: vehicle.id, dto: dto)) }
            }
            try context.save(); message = nil
        }
        catch {
            let server = profile.id.uuidString, car = vehicle.id
            let cached = (try? context.fetch(FetchDescriptor<FirmwareUpdateRecord>(predicate: #Predicate { $0.serverID == server && $0.carID == car }, sortBy: [SortDescriptor(\.endDate, order: .reverse)]))) ?? []
            updates = cached.map { FirmwareUpdateDTO(updateId: $0.updateID, startDate: FlexibleDate($0.startDate), endDate: FlexibleDate($0.endDate), version: $0.version) }
            message = error.localizedDescription
        }
        loading = false
    }
}
