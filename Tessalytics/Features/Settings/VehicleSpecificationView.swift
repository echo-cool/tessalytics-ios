import SwiftUI

/// Lets the owner state what the car was rated at when new.
///
/// Every as-new figure the app derives is the best its recorded history can
/// support, and that is simply wrong when logging began after the pack had aged:
/// a car rated 84 kWh new reads as 74 if recording started at 15,000 miles.
/// Health, capacity lost, range lost and equivalent cycles all inherit the error,
/// so this is a correction rather than a preference.
struct VehicleSpecificationView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var capacityText = ""
    @State private var rangeText = ""
    @State private var loaded = false

    private var battery: FleetStatistics.BatteryHealth? { environment.fleet.battery }
    private var distanceUnit: String { (environment.statusUnits ?? .metricDefaults).lengthSymbol }

    private var capacityValue: Double? { Double(capacityText.replacingOccurrences(of: ",", with: ".")) }
    private var rangeValue: Double? { Double(rangeText.replacingOccurrences(of: ",", with: ".")) }

    private var edited: VehicleSpecification {
        VehicleSpecification.sanitised(capacityNew: capacityValue, maxRangeNew: rangeValue)
    }

    /// Whether what is typed differs from what is stored, so Save is only offered
    /// when it would do something.
    private var hasChanges: Bool { edited != environment.selectedSpecification }

    private var capacityIsRejected: Bool {
        !capacityText.isEmpty && edited.capacityNew == nil
    }

    private var rangeIsRejected: Bool {
        !rangeText.isEmpty && edited.maxRangeNew == nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Capacity when new") {
                    HStack(spacing: 4) {
                        TextField(placeholder(battery?.derivedCapacityNew, digits: 1), text: $capacityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96)
                            .accessibilityIdentifier("specification-capacity-field")
                        Text("kWh").foregroundStyle(.secondary)
                    }
                }
                if capacityIsRejected {
                    Text("Between 1 and 400 kWh.")
                        .font(.caption)
                        .foregroundStyle(TessalyticsTheme.critical)
                }
                LabeledContent("Range when new") {
                    HStack(spacing: 4) {
                        TextField(placeholder(battery?.derivedMaxRangeNew, digits: 0), text: $rangeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96)
                            .accessibilityIdentifier("specification-range-field")
                        Text(distanceUnit).foregroundStyle(.secondary)
                    }
                }
                if rangeIsRejected {
                    Text(AppText.format("Between 1 and 2000 %@.", distanceUnit))
                        .font(.caption)
                        .foregroundStyle(TessalyticsTheme.critical)
                }
            } header: {
                Text("Manufacturer rating")
            } footer: {
                Text("Leave blank to use the derived figures.")
            }

            packSection

            Section("Derived from your history") {
                DerivedRow(
                    title: "Capacity when new",
                    value: format(battery?.derivedCapacityNew, unit: "kWh", digits: 1)
                )
                DerivedRow(
                    title: "Range when new",
                    value: format(battery?.derivedMaxRangeNew, unit: distanceUnit, digits: 0)
                )
                DerivedRow(
                    title: "Capacity now",
                    value: format(battery?.capacityNow, unit: "kWh", digits: 1)
                )
                if let health = previewHealth {
                    DerivedRow(
                        title: "Health with these figures",
                        value: ValueFormatting.percentage(health / 100, digits: 1),
                        emphasised: true
                    )
                }
            }

            if !environment.selectedSpecification.isEmpty {
                Section {
                    Button("Use derived values", role: .destructive) {
                        capacityText = ""
                        rangeText = ""
                        environment.saveSpecification(.empty)
                    }
                }
            }
        }
        .navigationTitle("Vehicle rating")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    environment.saveSpecification(edited)
                    dismiss()
                }
                .disabled(!hasChanges || capacityIsRejected || rangeIsRejected)
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            let stored = environment.selectedSpecification
            capacityText = stored.capacityNew.map { trimmed($0, digits: 1) } ?? ""
            rangeText = stored.maxRangeNew.map { trimmed($0, digits: 0) } ?? ""
        }
    }

    /// What the car was built with, according to the VIN and the shipped table.
    ///
    /// Offered rather than applied. The table is good but it is not the car: a
    /// model year spans quarters in which Tesla changed suppliers, a trim badge is
    /// often absent, and this number is the denominator of every health figure on
    /// every screen. So it fills the field on a tap and the owner can see what it
    /// filled it with.
    @ViewBuilder private var packSection: some View {
        if let vin = environment.selectedVIN {
            Section {
                LabeledContent("Model", value: AppText.format("Model %@", vin.model))
                LabeledContent("Built at", value: vin.factory.displayName)
                LabeledContent("Model year", value: String(vin.modelYear))

                Picker("Variant", selection: variantBinding) {
                    Text("Not set").tag(VehicleVariant?.none)
                    ForEach(VehicleVariant.choices(forModel: vin.model)) { variant in
                        Text(variant.displayName).tag(VehicleVariant?.some(variant))
                    }
                }
                .accessibilityIdentifier("specification-variant-picker")

                packRows
            } header: {
                Label("From your VIN", systemImage: "barcode.viewfinder")
            } footer: {
                Text(packFooter)
            }
        }
    }

    private var variantBinding: Binding<VehicleVariant?> {
        Binding(
            get: { environment.selectedPackVariant },
            set: { environment.savePackVariant($0) }
        )
    }

    @ViewBuilder private var packRows: some View {
        if let match = environment.selectedPackMatch {
            ForEach(match.candidates, id: \.code) { pack in
                Button {
                    capacityText = trimmed(pack.capacityKWh, digits: 1)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ValueFormatting.number(pack.capacityKWh, unit: "kWh", digits: 1))
                                .foregroundStyle(.primary)
                            Text("\(pack.cell) · \(pack.chemistry)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Use")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TessalyticsTheme.accent)
                    }
                    .contentShape(.rect)
                }
                .accessibilityIdentifier("specification-pack-\(pack.code)")
            }
        } else if environment.selectedPackVariant == nil {
            Text("Choose a variant to look up the pack.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No pack recorded for this variant, factory and year.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var packFooter: String {
        guard let match = environment.selectedPackMatch else {
            return "A VIN does not name the variant, so it has to be confirmed."
        }
        if match.isAmbiguous {
            return "More than one pack was fitted at \(match.factory.displayName) during \(match.modelYear). A delivery invoice or the original range figure says which."
        }
        return "Tapping fills the field above. Nothing applies until you save."
    }

    /// Health as it would read once saved, so the effect is visible before the
    /// figure propagates to every other screen.
    private var previewHealth: Double? {
        guard let now = battery?.capacityNow else { return nil }
        guard let asNew = edited.capacityNew ?? battery?.derivedCapacityNew, asNew > 0 else { return nil }
        return min(now / asNew, 1) * 100
    }

    private func placeholder(_ value: Double?, digits: Int) -> String {
        value.map { trimmed($0, digits: digits) } ?? "—"
    }

    private func trimmed(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }

    private func format(_ value: Double?, unit: String, digits: Int) -> String {
        guard let value else { return "Not available" }
        return "\(trimmed(value, digits: digits)) \(unit)"
    }
}

private struct DerivedRow: View {
    let title: String
    let value: String
    var emphasised = false

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(emphasised ? TessalyticsTheme.positive : .secondary)
                .fontWeight(emphasised ? .semibold : .regular)
        }
    }
}
