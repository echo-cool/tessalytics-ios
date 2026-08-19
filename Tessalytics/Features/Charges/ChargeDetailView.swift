import Charts
import SwiftData
import SwiftUI

struct ChargeDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    let chargeID: Int
    @State private var detail: ChargeDetailDTO?
    @State private var loading = true
    @State private var errorMessage: String?

    private var pollingKey: ChargePollingKey {
        ChargePollingKey(isActive: scenePhase == .active, isComplete: detail?.endDate?.value != nil)
    }

    var body: some View {
        TessalyticsScreen {
            ScrollView {
                if loading {
                    LoadingPanel(title: "Loading charging session", symbol: "bolt.car.fill")
                        .padding()
                } else if let detail {
                    VStack(spacing: 18) {
                    HStack { Label(detail.address ?? "Location not reported", systemImage: "mappin.and.ellipse"); Spacer(); if detail.endDate == nil { StatusBadge(text: "In progress", color: TessalyticsTheme.positive) } }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Energy added", value: ValueFormatting.number(detail.chargeEnergyAdded, unit: "kWh"), symbol: "bolt.fill")
                        MetricCard(title: "Energy drawn", value: ValueFormatting.number(detail.chargeEnergyUsed, unit: "kWh"), symbol: "powerplug.fill")
                        MetricCard(title: "Duration", value: ValueFormatting.duration(minutes: detail.durationMin), symbol: "clock")
                        MetricCard(title: "Cost", value: ValueFormatting.currency(detail.cost), symbol: "creditcard")
                        MetricCard(title: "Efficiency", value: efficiency(detail), symbol: "gauge.with.dots.needle.67percent")
                        MetricCard(title: "Price / kWh", value: price(detail), symbol: "dollarsign.arrow.circlepath")
                    }
                    sampleChart("Battery level", unit: "%", values: detail.chargeDetails.compactMap { point in point.batteryLevel.map { (point.detailId, Double($0)) } })
                    sampleChart("Charging power", unit: "kW", values: detail.chargeDetails.compactMap { point in point.chargerDetails?.chargerPower.map { (point.detailId, $0) } })
                    sampleChart("Voltage", unit: "V", values: detail.chargeDetails.compactMap { point in point.chargerDetails?.chargerVoltage.map { (point.detailId, $0) } })
                    sampleChart("Current", unit: "A", values: detail.chargeDetails.compactMap { point in point.chargerDetails?.chargerActualCurrent.map { (point.detailId, $0) } })
                    chargerDetails(detail)
                    }
                    .padding()
                } else {
                    EmptyState(title: "Session unavailable", message: errorMessage ?? "This charging session could not be loaded.", symbol: "bolt.slash")
                }
            }
        }
        .navigationTitle("Charge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarLeading) { TessalyticsBackButton() }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { TessalyticsBackButton() }
            }
        }
            .task { await load() }
            .task(id: pollingKey) { await pollWhileVisible() }
    }
    private func sampleChart(_ title: String, unit: String, values: [(Int, Double)]) -> some View {
        SectionCard(title, symbol: "chart.xyaxis.line", tint: TessalyticsTheme.positive) {
            if values.isEmpty {
                Text("No samples reported").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(values, id: \.0) { item in
                    AreaMark(x: .value("Sample", item.0), y: .value(title, item.1))
                        .foregroundStyle(.linearGradient(colors: [TessalyticsTheme.positive.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Sample", item.0), y: .value(title, item.1))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TessalyticsTheme.positive)
                }
                .chartXAxis(.hidden)
                .tessalyticsChartStyle()
                .frame(height: 180)
                .accessibilityLabel("\(title) chart with \(values.count) samples in \(unit)")
            }
        }
    }
    private func load() async {
        guard let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle else { return }
        do {
            detail = try await ChargeRepository(context: context).detail(client: environment.client(for: profile), serverID: profile.id, carID: vehicle.id, chargeID: chargeID)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func pollWhileVisible() async {
        guard pollingKey.isActive, !pollingKey.isComplete else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
                try Task.checkCancellation()
            } catch {
                return
            }
            await load()
            if detail?.endDate?.value != nil { return }
        }
    }
    private func efficiency(_ detail: ChargeDetailDTO) -> String { guard let added = detail.chargeEnergyAdded, let used = detail.chargeEnergyUsed, used > 0 else { return "Unavailable" }; return (added / used).formatted(.percent.precision(.fractionLength(1))) }
    private func price(_ detail: ChargeDetailDTO) -> String { guard let cost = detail.cost, let used = detail.chargeEnergyUsed, used > 0 else { return "Unavailable" }; return ValueFormatting.currency(cost / used) }
    private func chargerDetails(_ detail: ChargeDetailDTO) -> some View {
        let sample = detail.chargeDetails.last
        return GroupBox("Charger") {
            VStack(spacing: 10) {
                HStack { Text("Type").foregroundStyle(.secondary); Spacer(); Text(sample?.fastChargerInfo?.fastChargerType ?? sample?.connChargeCable ?? "Not reported") }
                HStack { Text("Brand").foregroundStyle(.secondary); Spacer(); Text(sample?.fastChargerInfo?.fastChargerBrand ?? "Not reported") }
                HStack { Text("Outside temperature").foregroundStyle(.secondary); Spacer(); Text(ValueFormatting.number(sample?.outsideTemp, unit: "°")) }
            }
        }
    }
}

private struct ChargePollingKey: Hashable {
    let isActive: Bool
    let isComplete: Bool
}
