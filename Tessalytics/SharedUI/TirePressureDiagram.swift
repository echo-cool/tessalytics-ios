import SwiftUI

/// The car from above, with a pressure at each corner.
///
/// Four numbers in a row cannot say which corner is which; a shape with the
/// readings placed where the wheels are does not need to. A tyre with no reading
/// is drawn hollow, because TeslaMate reports zero for a sensor it has not heard
/// from and a confident "0.0" is worse than a visible gap.
struct TirePressureDiagram: View {
    let pressures: TPMSDTO?
    let units: UnitsDTO?
    /// Overall height; the car scales to fit.
    var height: CGFloat = 96

    private var unit: String { (units ?? .metricDefaults).pressureSymbol }
    private var bodyWidth: CGFloat { height * 0.46 }

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: height * 0.28) {
                reading(for: .frontLeft)
                reading(for: .rearLeft)
            }
            carBody
            VStack(spacing: height * 0.28) {
                reading(for: .frontRight)
                reading(for: .rearRight)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tyre pressure")
        .accessibilityValue(accessibilityValue)
    }

    /// A plan view: rounded body, a windscreen line, and four wheels.
    private var carBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: bodyWidth * 0.42, style: .continuous)
                .stroke(TessalyticsTheme.steel.opacity(0.45), lineWidth: 1.5)
                .frame(width: bodyWidth, height: height * 0.86)

            RoundedRectangle(cornerRadius: bodyWidth * 0.2, style: .continuous)
                .stroke(TessalyticsTheme.steel.opacity(0.3), lineWidth: 1)
                .frame(width: bodyWidth * 0.58, height: height * 0.3)
                .offset(y: -height * 0.06)

            ForEach(Corner.allCases, id: \.self) { corner in
                Capsule()
                    .fill(tint(for: corner))
                    .frame(width: bodyWidth * 0.16, height: height * 0.19)
                    .offset(
                        x: corner.isLeft ? -bodyWidth * 0.5 : bodyWidth * 0.5,
                        y: corner.isFront ? -height * 0.29 : height * 0.29
                    )
            }
        }
        .frame(width: bodyWidth)
    }

    private enum Corner: CaseIterable {
        case frontLeft, frontRight, rearLeft, rearRight
        var isLeft: Bool { self == .frontLeft || self == .rearLeft }
        var isFront: Bool { self == .frontLeft || self == .frontRight }
    }

    private func value(for corner: Corner) -> Double? {
        switch corner {
        case .frontLeft: TPMSDTO.reported(pressures?.tpmsPressureFl)
        case .frontRight: TPMSDTO.reported(pressures?.tpmsPressureFr)
        case .rearLeft: TPMSDTO.reported(pressures?.tpmsPressureRl)
        case .rearRight: TPMSDTO.reported(pressures?.tpmsPressureRr)
        }
    }

    /// The car's own soft-pressure warning for a corner, when it reports one.
    private func isWarning(_ corner: Corner) -> Bool {
        switch corner {
        case .frontLeft: pressures?.tpmsWarningFl == true
        case .frontRight: pressures?.tpmsWarningFr == true
        case .rearLeft: pressures?.tpmsWarningRl == true
        case .rearRight: pressures?.tpmsWarningRr == true
        }
    }

    private func tint(for corner: Corner) -> Color {
        if isWarning(corner) { return TessalyticsTheme.warning }
        return value(for: corner) == nil ? TessalyticsTheme.steel.opacity(0.25) : TessalyticsTheme.steel.opacity(0.8)
    }

    private func reading(for corner: Corner) -> some View {
        let value = value(for: corner)
        let warns = isWarning(corner)
        return VStack(spacing: -1) {
            HStack(spacing: 2) {
                // The car said this one is soft. Colour alone would not carry it
                // to a reader who cannot see the difference, so the mark does.
                if warns {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TessalyticsTheme.warning)
                }
                Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")
                    .font(.caption.weight(warns ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(warns ? TessalyticsTheme.warning : (value == nil ? .secondary : .primary))
            }
            Text(unit)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 30)
        .accessibilityHidden(true)
    }

    private var accessibilityValue: String {
        let readings = Corner.allCases.compactMap { corner -> String? in
            guard let value = value(for: corner) else { return nil }
            let name: String = switch corner {
            case .frontLeft: "front left"
            case .frontRight: "front right"
            case .rearLeft: "rear left"
            case .rearRight: "rear right"
            }
            let warning = isWarning(corner) ? ", low pressure warning" : ""
            return "\(name) \(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)\(warning)"
        }
        return readings.isEmpty ? "No readings" : readings.joined(separator: ", ")
    }
}
