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
                    VStack(spacing: TessalyticsLayout.stackSpacing) {
                    SurfaceCard(tint: TessalyticsTheme.positive) {
                        HStack(spacing: 10) {
                            Label(detail.address ?? "Location not reported", systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if detail.endDate == nil {
                                StatusBadge(text: "In progress", color: TessalyticsTheme.positive)
                            }
                        }
                    }
                    MetricGrid {
                        MetricCard(
                            title: "Energy added",
                            value: ValueFormatting.number(detail.chargeEnergyAdded, unit: "kWh"),
                            symbol: "bolt.fill",
                            detail: batteryGainDetail(detail),
                            tint: TessalyticsTheme.positive
                        )
                        MetricCard(
                            title: "Energy drawn",
                            value: ValueFormatting.number(detail.chargeEnergyUsed, unit: "kWh"),
                            symbol: "powerplug.fill",
                            detail: efficiency(detail),
                            tint: TessalyticsTheme.positive
                        )
                        MetricCard(
                            title: "Duration",
                            value: ValueFormatting.duration(minutes: detail.durationMin),
                            symbol: "clock",
                            detail: averagePowerDetail(detail),
                            tint: TessalyticsTheme.neutral
                        )
                        MetricCard(
                            title: "Peak power",
                            value: peakPower(detail),
                            symbol: "gauge.with.dots.needle.67percent",
                            detail: chargerKindDetail(detail),
                            tint: TessalyticsTheme.warning
                        )
                        MetricCard(
                            title: "Cost",
                            value: ValueFormatting.chargeCost(detail.cost),
                            symbol: "creditcard",
                            detail: price(detail),
                            tint: TessalyticsTheme.steel
                        )
                        MetricCard(
                            title: "Started",
                            value: startTime(detail),
                            symbol: "calendar",
                            detail: ValueFormatting.date(detail.startDate?.value),
                            tint: TessalyticsTheme.neutral
                        )
                    }
                    // Level and power together: the moment the taper starts lines
                    // up with the level it started at, which is the thing worth
                    // knowing. They were two charts, read one at a time.
                    SectionCard(
                        "Charging curve",
                        subtitle: "Level against power",
                        symbol: "chart.xyaxis.line",
                        tint: TessalyticsTheme.positive
                    ) {
                        ChargeCurveChart(
                            points: detail.curvePoints(),
                            peakPower: detail.chargeDetails.compactMap { $0.chargerDetails?.chargerPower }.max(),
                            height: 220
                        )
                    }
                    sampleChart(
                        "Voltage",
                        unit: "V",
                        tint: TessalyticsTheme.chartNeutral,
                        baseline: .focused,
                        values: series(detail, whileCharging: true) { $0.chargerDetails?.chargerVoltage }
                    )
                    sampleChart(
                        "Current",
                        unit: "A",
                        tint: TessalyticsTheme.steel,
                        values: series(detail, whileCharging: true) { $0.chargerDetails?.chargerActualCurrent }
                    )
                    chargerDetails(detail)
                    }
                    .tessalyticsScreenPadding()
                    .tessalyticsReadableWidth(TessalyticsLayout.wideReadableWidth)
                } else {
                    EmptyState(title: "Session unavailable", message: errorMessage ?? "This charging session could not be loaded.", symbol: "bolt.slash")
                }
            }
        }
        .navigationTitle("Charge")
        .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .task(id: pollingKey) { await pollWhileVisible() }
    }
    /// Samples paired with their recording time, so the x-axis means something.
    /// Samples paired with their recording time.
    ///
    /// `whileCharging` keeps only the samples taken while the charger was
    /// delivering.
    ///
    /// Voltage and current are charger measurements, and they collapse the moment
    /// it stops — which is not a reading but the end of the session. Plotting the
    /// collapse dragged the axis to zero and drew a cliff. TeslaMate's AC current
    /// sensor also reads nothing throughout a DC fast charge, and with the filter
    /// that chart correctly has no samples at all rather than a flat zero line.
    private func series(
        _ detail: ChargeDetailDTO,
        whileCharging: Bool = false,
        _ value: (ChargePointDTO) -> Double?
    ) -> [ChartSample] {
        detail.chargeDetails.enumerated().compactMap { index, point in
            guard let date = point.date?.value, let measurement = value(point) else { return nil }
            if whileCharging {
                guard measurement > 0, (point.chargerDetails?.chargerPower ?? 0) > 0 else { return nil }
            }
            return ChartSample(id: index, date: date, value: measurement)
        }
    }

    @ViewBuilder
    private func sampleChart(
        _ title: String,
        unit: String,
        tint: Color = TessalyticsTheme.positive,
        baseline: ChartBaseline = .zero,
        values: [ChartSample]
    ) -> some View {
        // A card that could only say "no samples" is worth omitting entirely: an
        // AC current chart tells a Supercharger session's owner nothing.
        if !values.isEmpty {
            // Tappable, like a drive's charts: the same gesture has to mean the
            // same thing on both screens, or neither is discoverable.
            NavigationSectionCard(
                title,
                subtitle: "Tap to read values · \(values.count.formatted()) samples",
                symbol: "chart.xyaxis.line",
                tint: tint
            ) {
                ChartExplorerView(
                    chart: .timeSeries(title: title, unit: unit, tint: tint, baseline: baseline, samples: values)
                )
            } content: {
                Chart(downsampled(values)) { sample in
                    if baseline == .zero {
                        AreaMark(x: .value("Time", sample.date), y: .value(title, sample.value), stacking: .unstacked)
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.linearGradient(colors: [tint.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom))
                    }
                    LineMark(x: .value("Time", sample.date), y: .value(title, sample.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tint)
                }
                .chartValueDomain(baseline == .focused ? focusedChartDomain(for: values.map(\.value)) : nil)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .tessalyticsChartAxes(x: "Time of day", y: "\(title) (\(unit))")
                .tessalyticsChartStyle()
                .frame(height: 170)
                .accessibilityLabel("\(title) chart with \(values.count) samples in \(unit)")

                ChartLegend("\(title) (\(unit))", color: tint)
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
    /// Share of drawn energy that reached the pack.
    private func efficiency(_ detail: ChargeDetailDTO) -> String {
        guard let added = detail.chargeEnergyAdded, let used = detail.chargeEnergyUsed, used > 0 else {
            return "Draw not reported"
        }
        return "\((added / used).formatted(.percent.precision(.fractionLength(0)))) reached pack"
    }

    private func price(_ detail: ChargeDetailDTO) -> String {
        guard let cost = detail.cost, let used = detail.chargeEnergyUsed, used > 0 else {
            return "No cost configured"
        }
        return "\(ValueFormatting.currency(cost / used)) per kWh"
    }

    private func batteryGainDetail(_ detail: ChargeDetailDTO) -> String {
        let levels = detail.chargeDetails.compactMap(\.batteryLevel)
        guard let first = levels.first, let last = levels.last else { return "Charge added" }
        return "\(first)% → \(last)%"
    }

    private func peakPower(_ detail: ChargeDetailDTO) -> String {
        let powers = detail.chargeDetails.compactMap { $0.chargerDetails?.chargerPower }
        guard let peak = powers.max() else { return "Unavailable" }
        return ValueFormatting.number(peak, unit: "kW", digits: 0)
    }

    private func averagePowerDetail(_ detail: ChargeDetailDTO) -> String {
        guard let added = detail.chargeEnergyAdded,
              let minutes = detail.durationMin, minutes > 0 else { return "Session length" }
        let average = added / (Double(minutes) / 60)
        return "Avg \(ValueFormatting.number(average, unit: "kW", digits: 1))"
    }

    private func chargerKindDetail(_ detail: ChargeDetailDTO) -> String {
        let sample = detail.chargeDetails.last
        if let type = sample?.fastChargerInfo?.fastChargerType?.nilIfEmpty { return type }
        if let cable = sample?.connChargeCable?.nilIfEmpty { return cable }
        return sample?.fastChargerInfo?.fastChargerPresent == true ? "Fast charger" : "Charger not reported"
    }

    private func startTime(_ detail: ChargeDetailDTO) -> String {
        guard let date = detail.startDate?.value else { return "Not reported" }
        return date.formatted(date: .omitted, time: .shortened)
    }
    private func chargerDetails(_ detail: ChargeDetailDTO) -> some View {
        let sample = detail.chargeDetails.last
        return GroupBox("Charger") {
            VStack(spacing: 10) {
                HStack { Text("Type").foregroundStyle(.secondary); Spacer(); Text(sample?.fastChargerInfo?.fastChargerType ?? sample?.connChargeCable ?? "Not reported") }
                HStack { Text("Brand").foregroundStyle(.secondary); Spacer(); Text(sample?.fastChargerInfo?.fastChargerBrand ?? "Not reported") }
                HStack { Text("Outside temperature").foregroundStyle(.secondary); Spacer(); Text(ValueFormatting.temperature(sample?.outsideTemp, units: environment.statusUnits)) }
            }
        }
    }
}

private struct ChargePollingKey: Hashable {
    let isActive: Bool
    let isComplete: Bool
}
