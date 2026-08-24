import Charts
import SwiftData
import SwiftUI

struct IntelligenceView: View {
    var embedded = false

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var snapshot: VehicleIntelligenceSnapshot?
    @State private var isLoading = true
    @State private var distanceUnit = UnitsDTO.metricDefaults.lengthSymbol

    var body: some View {
        TessalyticsScreen(showsTopAccent: !embedded) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !embedded {
                        IntelligenceHero(snapshot: snapshot)
                    }

                    if let snapshot {
                        ForecastGrid(forecasts: snapshot.forecasts, distanceUnit: distanceUnit)
                        DistancePredictionChart(points: snapshot.distanceSeries, distanceUnit: distanceUnit)
                        IntelligenceSignals(insights: snapshot.insights)
                        if !embedded {
                            NotificationCallout()
                            IntelligenceMethodology(snapshot: snapshot)
                        }
                    } else if isLoading {
                        LoadingPanel(title: "Analyzing synchronized history", symbol: "sparkles.rectangle.stack.fill")
                    } else {
                        EmptyState(
                            title: "Not enough synchronized history",
                            message: "Sync completed drives and charging sessions to create predictions and personalized signals.",
                            symbol: "chart.line.downtrend.xyaxis"
                        )
                    }
                }
                .tessalyticsScreenPadding()
                .tessalyticsReadableWidth()
            }
        }
        .navigationTitle(embedded ? "Analysis" : "Intelligence")
        .task(id: environment.selectedVehicle?.id) { await load() }
        .accessibilityIdentifier("intelligence-screen")
    }

    @MainActor
    private func load() async {
        isLoading = true
        let samples: (drives: [AnalyticsDriveSample], charges: [AnalyticsChargeSample])
        if environment.isDemoMode {
            samples = DemoAnalyticsFactory.samples()
            distanceUnit = DemoExperience.units.lengthSymbol
        } else if let profile = environment.selectedProfile, let vehicle = environment.selectedVehicle {
            let driveRecords = DriveRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
            let chargeRecords = ChargeRepository(context: context).cached(serverID: profile.id, carID: vehicle.id)
            samples = (
                driveRecords.compactMap { record in
                    guard let date = record.startDate else { return nil }
                    return AnalyticsDriveSample(
                        id: record.driveID,
                        date: date,
                        distance: record.distance,
                        durationMinutes: record.durationMinutes,
                        energy: record.energy,
                        efficiency: record.efficiency,
                        destination: record.endAddress
                    )
                },
                chargeRecords.compactMap { record in
                    guard let date = record.startDate else { return nil }
                    return AnalyticsChargeSample(
                        id: record.chargeID,
                        date: date,
                        energy: record.energyAdded,
                        cost: record.cost,
                        durationMinutes: record.durationMinutes,
                        location: record.address
                    )
                }
            )
            let serverID = profile.id.uuidString
            let descriptor = FetchDescriptor<GlobalSettingsRecord>(predicate: #Predicate { $0.serverID == serverID })
            distanceUnit = (try? context.fetch(descriptor).first?.lengthUnit)
                ?? environment.statusUnits?.lengthSymbol
                ?? UnitsDTO.metricDefaults.lengthSymbol
        } else {
            samples = ([], [])
        }

        guard !samples.drives.isEmpty || !samples.charges.isEmpty else {
            snapshot = nil
            isLoading = false
            return
        }

        let result = await VehicleIntelligenceService.shared.analyze(
            drives: samples.drives,
            charges: samples.charges,
            status: environment.status,
            distanceUnit: distanceUnit
        )
        guard !Task.isCancelled else { return }
        snapshot = result
        isLoading = false

        let preferences = IntelligenceNotificationPreferences.stored()
        if preferences.enabled {
            await IntelligenceNotificationService.shared.publishInsightNotifications(
                insights: result.insights,
                vehicleName: environment.selectedVehicle?.name ?? "Your Tesla",
                preferences: preferences
            )
        }
    }
}

private struct IntelligenceHero: View {
    let snapshot: VehicleIntelligenceSnapshot?

    var body: some View {
        DashboardHeroCard(
            eyebrow: "Tessalytics Intelligence",
            title: snapshot == nil ? "Know what is likely next" : "Forecasts with evidence, not guesswork",
            subtitle: "Travel, charging, cost and efficiency forecasts.",
            symbol: "sparkles.rectangle.stack.fill",
            badge: snapshot?.confidence.rawValue ?? "Preparing"
        )
    }
}

private struct ForecastGrid: View {
    let forecasts: [IntelligenceForecast]
    let distanceUnit: String

    var body: some View {
        LazyVGrid(
            columns: TessalyticsLayout.metricColumns(minimum: 150),
            spacing: TessalyticsLayout.gridSpacing
        ) {
            ForEach(forecasts) { forecast in
                ForecastCard(forecast: forecast, distanceUnit: distanceUnit)
            }
        }
    }
}

private struct ForecastCard: View {
    let forecast: IntelligenceForecast
    let distanceUnit: String

    private var presentation: (title: String, value: String, symbol: String, tint: Color) {
        switch forecast.kind {
        case .weeklyDistance:
            return (
                "Next 7 days",
                ValueFormatting.number(forecast.value, unit: distanceUnit),
                "road.lanes",
                TessalyticsTheme.accent
            )
        case .nextCharge:
            return (
                "Next likely charge",
                forecast.date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Learning",
                "bolt.car.fill",
                TessalyticsTheme.positive
            )
        case .monthlyChargingCost:
            return (
                "Next 30-day cost",
                forecast.value.map { ValueFormatting.currency($0) } ?? "Learning",
                "dollarsign.circle.fill",
                TessalyticsTheme.neutral
            )
        case .typicalEfficiency:
            let unit = distanceUnit.isEmpty ? "reported" : "Wh/\(distanceUnit)"
            return (
                "Typical efficiency",
                ValueFormatting.number(forecast.value, unit: unit),
                "leaf.fill",
                TessalyticsTheme.warning
            )
        }
    }

    var body: some View {
        let content = presentation
        SurfaceCard(tint: content.tint) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: content.symbol)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(content.tint)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    ConfidenceBadge(confidence: forecast.confidence)
                }
                Text(content.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(content.value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                Text(forecast.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ConfidenceBadge: View {
    let confidence: ForecastConfidence

    private var tint: Color {
        switch confidence {
        case .high: TessalyticsTheme.positive
        case .medium: TessalyticsTheme.steel
        case .low: TessalyticsTheme.warning
        }
    }

    var body: some View {
        Text(confidence == .high ? "High" : confidence == .medium ? "Medium" : "Early")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct DistancePredictionChart: View {
    let points: [IntelligenceDistancePoint]
    let distanceUnit: String
    @State private var selectedDate: Date?

    private var selectedPoint: IntelligenceDistancePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var maximum: Double {
        max(1, points.map { $0.upperBound ?? $0.value }.max() ?? 1)
    }

    private var resolvedDistanceUnit: String {
        distanceUnit.isEmpty ? UnitsDTO.metricDefaults.lengthSymbol : distanceUnit
    }

    var body: some View {
        SectionCard(
            "Travel forecast",
            subtitle: "Daily distance vs. seven-day pattern",
            symbol: "chart.line.uptrend.xyaxis",
            tint: TessalyticsTheme.accent
        ) {
            PredictionSelectionReadout(
                title: selectedPoint?.date.formatted(date: .abbreviated, time: .omitted) ?? "Select a day",
                value: selectedPoint.map { ValueFormatting.number($0.value, unit: distanceUnit) },
                detail: selectedPoint?.series.rawValue
            )

            Chart(points) { point in
                if point.series == .forecast, let low = point.lowerBound, let high = point.upperBound {
                    AreaMark(
                        x: .value("Forecast date", point.date),
                        yStart: .value("Likely low distance", low),
                        yEnd: .value("Likely high distance", high)
                    )
                    .foregroundStyle(TessalyticsTheme.accent.opacity(0.12))
                }

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Daily distance", point.value),
                    series: .value("Series", point.series.rawValue)
                )
                .foregroundStyle(by: .value("Series", point.series.rawValue))
                .interpolationMethod(.monotone)
                .lineStyle(point.series == .forecast ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 2))

                if point.series == .forecast {
                    PointMark(
                        x: .value("Forecast date", point.date),
                        y: .value("Predicted distance", point.value)
                    )
                    .foregroundStyle(TessalyticsTheme.accent)
                }

                if let selectedDate {
                    RuleMark(x: .value("Selected date", selectedDate))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartForegroundStyleScale([
                IntelligenceDistancePoint.Series.observed.rawValue: TessalyticsTheme.chartNeutral,
                IntelligenceDistancePoint.Series.forecast.rawValue: TessalyticsTheme.accent
            ])
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
            .chartYScale(domain: 0...(maximum * 1.1))
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .tessalyticsChartAxes(x: "Date", y: "Daily distance (\(resolvedDistanceUnit))")
            .tessalyticsChartStyle()
            .frame(height: 280)
            .accessibilityLabel("Observed and forecast daily driving distance")
            .accessibilityIdentifier("distance-forecast-chart")
            .sensoryFeedback(.selection, trigger: selectedDate)

            ChartLegend([
                .init("Observed", color: TessalyticsTheme.chartNeutral),
                .init("Forecast", color: TessalyticsTheme.accent),
                .init("Likely range", color: TessalyticsTheme.accent.opacity(0.25))
            ])

            Label("Shaded band shows the historical variability for matching weekdays.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct IntelligenceSignals: View {
    let insights: [VehicleInsight]

    var body: some View {
        SectionCard(
            "Signals and opportunities",
            subtitle: "Detected in recent data",
            symbol: "waveform.path.ecg.rectangle.fill",
            tint: TessalyticsTheme.warning
        ) {
            VStack(spacing: 12) {
                ForEach(insights) { insight in
                    IntelligenceSignalRow(insight: insight)
                }
            }
        }
        .accessibilityIdentifier("intelligence-signals")
    }
}

private struct PredictionSelectionReadout: View {
    let title: String
    let value: String?
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .accessibilityElement(children: .combine)
    }
}

private struct IntelligenceSignalRow: View {
    let insight: VehicleInsight

    private var tint: Color {
        switch insight.severity {
        case .positive: TessalyticsTheme.positive
        case .information: TessalyticsTheme.steel
        case .opportunity: TessalyticsTheme.accent
        case .warning: TessalyticsTheme.warning
        case .critical: TessalyticsTheme.critical
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(insight.title).font(.headline)
                Text(insight.message).font(.subheadline).foregroundStyle(.secondary)
                Text(insight.recommendation)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.06), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct NotificationCallout: View {
    var body: some View {
        NavigationLink { IntelligenceNotificationSettingsView() } label: {
            SurfaceCard(tint: TessalyticsTheme.neutral) {
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(TessalyticsTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(TessalyticsTheme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Turn insight into action").font(.headline)
                        Text("Get local alerts for low battery, predicted charging completion, updates, and important anomalies.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct IntelligenceMethodology: View {
    let snapshot: VehicleIntelligenceSnapshot

    var body: some View {
        SectionCard("How predictions work", symbol: "function", tint: TessalyticsTheme.neutral) {
            VStack(alignment: .leading, spacing: 12) {
                Label(AppText.format("%1$@ drive and %2$@ charge observations analyzed", "\(snapshot.driveObservations)", "\(snapshot.chargeObservations)"), systemImage: "externaldrive.fill.badge.checkmark")
                Label("Confidence falls when history is sparse", systemImage: "checkmark.shield.fill")
                if let latest = snapshot.latestActivity {
                    Label(AppText.format("Latest activity %@", latest.formatted(.relative(presentation: .named))), systemImage: "clock.fill")
                }
                Text("Estimates from local history — not guarantees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }
}
