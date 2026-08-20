import SwiftUI

/// State of charge as a ring rather than a bare number.
///
/// The ring carries three things a number cannot: how full the pack is at a
/// glance, whether that is comfortable or low, and — when a charge is running —
/// how far the current session still has to go.
struct BatteryRingGauge: View {
    /// 0...1. Nil draws the empty track, so an unknown level is visibly unknown
    /// rather than shown as zero.
    let level: Double?
    /// The charge limit, drawn as a tick on the ring when one is reported.
    var limit: Double?
    var isCharging = false
    var diameter: CGFloat = 96

    private var clamped: Double { min(max(level ?? 0, 0), 1) }

    private var tint: Color {
        if isCharging { return TessalyticsTheme.positive }
        guard let level else { return TessalyticsTheme.steel }
        if level <= 0.1 { return TessalyticsTheme.critical }
        if level <= 0.2 { return TessalyticsTheme.warning }
        return TessalyticsTheme.accent
    }

    private var lineWidth: CGFloat { max(diameter * 0.095, 7) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(TessalyticsTheme.steel.opacity(0.18), lineWidth: lineWidth)

            if level != nil {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.45), value: clamped)
            }

            if let limit, limit > 0, limit < 1 {
                // A tick, not an arc: the limit is a boundary, not a quantity.
                Capsule()
                    .fill(TessalyticsTheme.steel.opacity(0.55))
                    .frame(width: 2, height: lineWidth + 4)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(limit * 360))
            }

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(level.map { ($0 * 100).formatted(.number.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: diameter * 0.15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: diameter * 0.14))
                        .foregroundStyle(TessalyticsTheme.positive)
                }
            }
            .minimumScaleFactor(0.6)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let level else { return "Unavailable" }
        let percent = (level * 100).formatted(.number.precision(.fractionLength(0)))
        let charging = isCharging ? ", charging" : ""
        let limitText = limit.map { ", limit \(($0 * 100).formatted(.number.precision(.fractionLength(0)))) percent" } ?? ""
        return "\(percent) percent\(charging)\(limitText)"
    }
}
