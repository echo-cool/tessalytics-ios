import Foundation

enum ForecastConfidence: String, Sendable, Equatable {
    case low = "Early estimate"
    case medium = "Moderate confidence"
    case high = "High confidence"
}

enum IntelligenceForecastKind: String, Sendable, Equatable, Identifiable {
    case weeklyDistance
    case nextCharge
    case monthlyChargingCost
    case typicalEfficiency

    var id: String { rawValue }
}

struct IntelligenceForecast: Identifiable, Sendable, Equatable {
    let kind: IntelligenceForecastKind
    let value: Double?
    let date: Date?
    let lowerBound: Double?
    let upperBound: Double?
    let unit: String
    let detail: String
    let confidence: ForecastConfidence

    var id: IntelligenceForecastKind { kind }
}

struct IntelligenceDistancePoint: Identifiable, Sendable, Equatable {
    enum Series: String, Sendable, Equatable {
        case observed = "Observed"
        case forecast = "Forecast"
    }

    let date: Date
    let value: Double
    let lowerBound: Double?
    let upperBound: Double?
    let series: Series

    var id: String { "\(series.rawValue)-\(date.timeIntervalSinceReferenceDate)" }
}

enum VehicleInsightSeverity: Int, Sendable, Equatable {
    case positive
    case information
    case opportunity
    case warning
    case critical
}

struct VehicleInsight: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let message: String
    let recommendation: String
    let symbol: String
    let severity: VehicleInsightSeverity
}

struct VehicleIntelligenceSnapshot: Sendable, Equatable {
    let generatedAt: Date
    let forecasts: [IntelligenceForecast]
    let distanceSeries: [IntelligenceDistancePoint]
    let insights: [VehicleInsight]
    let confidence: ForecastConfidence
    let driveObservations: Int
    let chargeObservations: Int
    let latestActivity: Date?
}

actor VehicleIntelligenceService {
    static let shared = VehicleIntelligenceService()

    func analyze(
        drives: [AnalyticsDriveSample],
        charges: [AnalyticsChargeSample],
        status: VehicleStatus?,
        distanceUnit: String,
        now: Date = .now
    ) -> VehicleIntelligenceSnapshot {
        VehicleIntelligenceEngine().make(
            drives: drives,
            charges: charges,
            status: status,
            distanceUnit: distanceUnit,
            now: now
        )
    }
}

struct VehicleIntelligenceEngine {
    var calendar = Calendar.current

    func make(
        drives: [AnalyticsDriveSample],
        charges: [AnalyticsChargeSample],
        status: VehicleStatus?,
        distanceUnit: String,
        now: Date = .now
    ) -> VehicleIntelligenceSnapshot {
        let sortedDrives = drives.sorted { $0.date < $1.date }
        let sortedCharges = charges.sorted { $0.date < $1.date }
        let distance = distancePrediction(drives: sortedDrives, now: now)
        let nextCharge = nextChargePrediction(charges: sortedCharges, now: now)
        let chargingCost = chargingCostPrediction(charges: sortedCharges, now: now)
        let efficiency = efficiencyPrediction(drives: sortedDrives, distanceUnit: distanceUnit, now: now)
        let overallConfidence = minimumConfidence([
            distance.forecast.confidence,
            nextCharge.confidence,
            chargingCost.confidence,
            efficiency.confidence
        ])

        return VehicleIntelligenceSnapshot(
            generatedAt: now,
            forecasts: [
                IntelligenceForecast(
                    kind: .weeklyDistance,
                    value: distance.forecast.value,
                    date: nil,
                    lowerBound: distance.forecast.lowerBound,
                    upperBound: distance.forecast.upperBound,
                    unit: distanceUnit,
                    detail: "From your seven-day pattern",
                    confidence: distance.forecast.confidence
                ),
                nextCharge,
                chargingCost,
                efficiency
            ],
            distanceSeries: distance.points,
            insights: insights(drives: sortedDrives, charges: sortedCharges, status: status, now: now),
            confidence: overallConfidence,
            driveObservations: sortedDrives.count,
            chargeObservations: sortedCharges.count,
            latestActivity: (sortedDrives.map(\.date) + sortedCharges.map(\.date)).max()
        )
    }

    private func distancePrediction(
        drives: [AnalyticsDriveSample],
        now: Date
    ) -> (forecast: IntelligenceForecast, points: [IntelligenceDistancePoint]) {
        let today = calendar.startOfDay(for: now)
        let historyStart = calendar.date(byAdding: .day, value: -55, to: today) ?? today
        let recentDrives = drives.filter { $0.date >= historyStart && $0.date < today.addingTimeInterval(86_400) }
        let grouped = Dictionary(grouping: recentDrives) { calendar.startOfDay(for: $0.date) }

        let historyDays = (0..<56).compactMap { offset -> (Date, Double)? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: historyStart) else { return nil }
            return (date, grouped[date, default: []].compactMap(\.distance).reduce(0, +))
        }
        let observed = historyDays.suffix(14).map { date, value in
            IntelligenceDistancePoint(date: date, value: value, lowerBound: nil, upperBound: nil, series: .observed)
        }

        let meanDaily = mean(historyDays.map { $0.1 }) ?? 0
        let dailyDeviation = standardDeviation(historyDays.map { $0.1 }, mean: meanDaily)
        let coefficientOfVariation = meanDaily > 0 ? dailyDeviation / meanDaily : .infinity
        let confidence: ForecastConfidence
        if recentDrives.count >= 30, coefficientOfVariation < 1.35 {
            confidence = .high
        } else if recentDrives.count >= 12 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let predictions = (1...7).compactMap { offset -> IntelligenceDistancePoint? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let matching = historyDays.filter { calendar.component(.weekday, from: $0.0) == weekday }.map { $0.1 }
            let expected = mean(matching) ?? meanDaily
            let deviation = standardDeviation(matching, mean: expected)
            return IntelligenceDistancePoint(
                date: date,
                value: max(0, expected),
                lowerBound: max(0, expected - deviation),
                upperBound: expected + deviation,
                series: .forecast
            )
        }
        let weekly = predictions.map(\.value).reduce(0, +)
        let low = predictions.compactMap(\.lowerBound).reduce(0, +)
        let high = predictions.compactMap(\.upperBound).reduce(0, +)
        let forecast = IntelligenceForecast(
            kind: .weeklyDistance,
            value: weekly,
            date: nil,
            lowerBound: low,
            upperBound: high,
            unit: "",
            detail: "From your seven-day pattern",
            confidence: confidence
        )
        return (forecast, observed + predictions)
    }

    private func nextChargePrediction(charges: [AnalyticsChargeSample], now: Date) -> IntelligenceForecast {
        var intervals: [TimeInterval] = []
        if charges.count > 1 {
            for index in 1..<charges.count {
                let interval = charges[index].date.timeIntervalSince(charges[index - 1].date)
                if interval >= 6 * 3_600, interval <= 14 * 86_400 {
                    intervals.append(interval)
                }
            }
        }
        guard let typicalInterval = median(intervals), let lastCharge = charges.last?.date else {
            return IntelligenceForecast(
                kind: .nextCharge,
                value: nil,
                date: nil,
                lowerBound: nil,
                upperBound: nil,
                unit: "",
                detail: "Needs more charging sessions",
                confidence: .low
            )
        }

        var predicted = lastCharge.addingTimeInterval(typicalInterval)
        while predicted <= now { predicted = predicted.addingTimeInterval(typicalInterval) }
        let deviations: [Double] = intervals.map { abs($0 - typicalInterval) }
        let variation: Double = median(deviations) ?? typicalInterval
        let confidence: ForecastConfidence
        if intervals.count >= 12, variation / typicalInterval < 0.35 {
            confidence = .high
        } else if intervals.count >= 5 {
            confidence = .medium
        } else {
            confidence = .low
        }
        return IntelligenceForecast(
            kind: .nextCharge,
            value: typicalInterval / 86_400,
            date: predicted,
            lowerBound: nil,
            upperBound: nil,
            unit: "",
            detail: "From your median interval",
            confidence: confidence
        )
    }

    private func chargingCostPrediction(charges: [AnalyticsChargeSample], now: Date) -> IntelligenceForecast {
        let start = calendar.date(byAdding: .day, value: -59, to: calendar.startOfDay(for: now)) ?? now
        let priced = charges.filter { $0.date >= start && $0.date <= now && $0.cost != nil }
        guard let first = priced.first?.date, !priced.isEmpty else {
            return IntelligenceForecast(
                kind: .monthlyChargingCost,
                value: nil,
                date: nil,
                lowerBound: nil,
                upperBound: nil,
                unit: "",
                detail: "Needs charging costs",
                confidence: .low
            )
        }
        let coveredDays = max(1, now.timeIntervalSince(first) / 86_400)
        let costs = priced.compactMap(\.cost)
        let projection = costs.reduce(0, +) / coveredDays * 30
        let confidence: ForecastConfidence = priced.count >= 16 ? .high : priced.count >= 6 ? .medium : .low
        return IntelligenceForecast(
            kind: .monthlyChargingCost,
            value: projection,
            date: nil,
            lowerBound: projection * 0.8,
            upperBound: projection * 1.2,
            unit: "",
            detail: "From the last 60 days",
            confidence: confidence
        )
    }

    private func efficiencyPrediction(drives: [AnalyticsDriveSample], distanceUnit: String, now: Date) -> IntelligenceForecast {
        let start = calendar.date(byAdding: .day, value: -89, to: now) ?? now
        let values = drives.filter { $0.date >= start && $0.date <= now }.compactMap(\.efficiency)
        let typical = median(values)
        let confidence: ForecastConfidence = values.count >= 30 ? .high : values.count >= 10 ? .medium : .low
        return IntelligenceForecast(
            kind: .typicalEfficiency,
            value: typical,
            date: nil,
            lowerBound: nil,
            upperBound: nil,
            unit: distanceUnit.isEmpty ? "reported" : "Wh/\(distanceUnit)",
            detail: "Median of recent drives",
            confidence: confidence
        )
    }

    private func insights(
        drives: [AnalyticsDriveSample],
        charges: [AnalyticsChargeSample],
        status: VehicleStatus?,
        now: Date
    ) -> [VehicleInsight] {
        var results: [VehicleInsight] = []

        if let battery = status?.batteryDetails?.batteryLevel,
           battery <= 20,
           status?.chargingDetails?.pluggedIn != true {
            results.append(
                VehicleInsight(
                    id: "low-battery",
                    title: "Low battery needs attention",
                    message: AppText.format("The last reported battery level is %@%% and the vehicle is not plugged in.", "\(battery)"),
                    recommendation: "Plan a charge before your next longer drive.",
                    symbol: "battery.25percent",
                    severity: battery <= 10 ? .critical : .warning
                )
            )
        }

        let efficiencyValues = drives.compactMap { drive in drive.efficiency.map { (drive.date, $0) } }
        let recentEfficiency = efficiencyValues.suffix(8).map { $0.1 }
        let baselineEfficiency = efficiencyValues.dropLast(min(8, efficiencyValues.count)).suffix(24).map { $0.1 }
        if let recent = mean(recentEfficiency), let baseline = mean(baselineEfficiency), baseline > 0, recent > baseline * 1.12 {
            let increase = (recent / baseline - 1) * 100
            results.append(
                VehicleInsight(
                    id: "efficiency-change",
                    title: "Energy use is trending higher",
                    message: AppText.format("Recent reported consumption is about %@%% above your prior baseline.", "\(Int(increase.rounded()))"),
                    recommendation: "Check tire pressure, temperature, speed, and climate use on recent trips.",
                    symbol: "bolt.trianglebadge.exclamationmark.fill",
                    severity: .warning
                )
            )
        }

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let recentCharges = charges.filter { $0.date >= thirtyDaysAgo && $0.date <= now }
        let previousCharges = charges.filter { $0.date >= sixtyDaysAgo && $0.date < thirtyDaysAgo }
        if let recentRate = pricePerKWh(recentCharges),
           let previousRate = pricePerKWh(previousCharges),
           previousRate > 0,
           recentRate > previousRate * 1.15 {
            let increase = (recentRate / previousRate - 1) * 100
            results.append(
                VehicleInsight(
                    id: "charging-cost-change",
                    title: "Charging price increased",
                    message: AppText.format("Your recent average price per kWh is %@%% above the preceding 30 days.", "\(Int(increase.rounded()))"),
                    recommendation: "Compare locations and shift flexible charging to the lowest-cost option.",
                    symbol: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90",
                    severity: .opportunity
                )
            )
        }

        if let savings = chargingSavingsOpportunity(charges: charges, now: now) {
            results.append(
                VehicleInsight(
                    id: "charging-location-savings",
                    title: "A lower-cost charging pattern is available",
                    message: AppText.format("Charging more often at %1$@ could save about %2$@%% per kWh versus your costliest regular location.", savings.location, "\(savings.percent)"),
                    recommendation: "Use this as a planning signal when location and timing are flexible.",
                    symbol: "leaf.circle.fill",
                    severity: .opportunity
                )
            )
        }

        if let latest = (drives.map(\.date) + charges.map(\.date)).max(), now.timeIntervalSince(latest) > 7 * 86_400 {
            results.append(
                VehicleInsight(
                    id: "stale-history",
                    title: "History may be stale",
                    message: "No completed drive or charge has been synchronized for more than seven days.",
                    recommendation: "Refresh history before relying on forecasts.",
                    symbol: "clock.badge.exclamationmark.fill",
                    severity: .information
                )
            )
        }

        if results.isEmpty {
            results.append(
                VehicleInsight(
                    id: "stable-patterns",
                    title: "Recent patterns look stable",
                    message: "No material efficiency, charging-cost, or data-freshness anomaly was detected.",
                    recommendation: "Keep synchronizing history to improve forecast confidence.",
                    symbol: "checkmark.seal.fill",
                    severity: .positive
                )
            )
        }

        return results.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    private func chargingSavingsOpportunity(
        charges: [AnalyticsChargeSample],
        now: Date
    ) -> (location: String, percent: Int)? {
        let start = calendar.date(byAdding: .day, value: -120, to: now) ?? now
        let complete = charges.filter { $0.date >= start && ($0.energy ?? 0) > 0 && $0.cost != nil }
        let grouped = Dictionary(grouping: complete) { normalizedPlace($0.location) }
        let rates = grouped.compactMap { location, values -> (String, Double)? in
            guard values.count >= 2, let rate = pricePerKWh(values) else { return nil }
            return (location, rate)
        }
        guard let cheapest = rates.min(by: { $0.1 < $1.1 }),
              let costliest = rates.max(by: { $0.1 < $1.1 }),
              cheapest.1 > 0,
              costliest.1 > cheapest.1 * 1.2 else { return nil }
        let percent = Int(((costliest.1 - cheapest.1) / costliest.1 * 100).rounded())
        return (cheapest.0, percent)
    }

    private func pricePerKWh(_ charges: [AnalyticsChargeSample]) -> Double? {
        let complete = charges.compactMap { charge -> (Double, Double)? in
            guard let energy = charge.energy, energy > 0, let cost = charge.cost else { return nil }
            return (energy, cost)
        }
        let energy = complete.map { $0.0 }.reduce(0, +)
        guard energy > 0 else { return nil }
        return complete.map { $0.1 }.reduce(0, +) / energy
    }

    private func normalizedPlace(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "Unreported" }
        return value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? value
    }

    private func minimumConfidence(_ values: [ForecastConfidence]) -> ForecastConfidence {
        if values.contains(.low) { return .low }
        if values.contains(.medium) { return .medium }
        return .high
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}
