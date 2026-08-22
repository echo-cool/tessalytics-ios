import SwiftUI

/// The car itself: what it is, what it was rated at, and what it is running.
///
/// Reached by tapping the name at the top of the hero card, which is where a
/// person looks for "tell me about this car" and which previously opened battery
/// health along with every other tap on that card.
struct VehicleSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var vehicle: Vehicle? { environment.selectedVehicle }
    private var status: VehicleStatus? { environment.status }
    private var units: UnitsDTO { environment.statusUnits ?? .metricDefaults }

    var body: some View {
        TessalyticsScreen {
            List {
                identitySection
                ratingSection
                softwareSection
                if environment.vehicles.count > 1 { pickerSection }
                coverageSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(vehicle?.name?.nilIfEmpty ?? "Vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("vehicle-settings-screen")
    }

    private var identitySection: some View {
        Section {
            LabeledContent("Name", value: vehicle?.name?.nilIfEmpty ?? "Not named")
            LabeledContent("Model", value: TeslaModelNaming.displayName(vehicle?.model) ?? "Not reported")
            if let trim = vehicle?.trim?.nilIfEmpty {
                LabeledContent("Trim", value: trim)
            }
            LabeledContent("Odometer", value: ValueFormatting.distance(status?.odometer, units: units, digits: 0))
        } header: {
            Label("This vehicle", systemImage: "car.fill")
        } footer: {
            Text("The name and model come from TeslaMate. Rename the car in the Tesla app and it follows here.")
        }
    }

    private var ratingSection: some View {
        Section {
            NavigationLink {
                VehicleSpecificationView()
            } label: {
                LabeledContent("Vehicle rating") {
                    Text(ratingSummary).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("vehicle-settings-rating")
        } header: {
            Label("Rating when new", systemImage: "gauge.with.dots.needle.100percent")
        } footer: {
            Text(
                "Every as-new figure the app derives is the best your recorded history can support, which is wrong when logging began after the pack had aged. Stating the manufacturer's rating corrects health, capacity lost and equivalent cycles together."
            )
        }
    }

    /// What the rating currently resolves to, so the row says something before it
    /// is opened.
    private var ratingSummary: String {
        let specification = environment.selectedSpecification
        let battery = environment.fleet.battery
        let capacity = specification.capacityNew ?? battery?.derivedCapacityNew
        guard let capacity else { return specification.isEmpty ? "Derived" : "Set" }
        let source = specification.capacityNew == nil ? "derived" : "stated"
        return "\(ValueFormatting.number(capacity, unit: "kWh", digits: 1)) \(source)"
    }

    private var softwareSection: some View {
        Section {
            NavigationLink {
                SoftwareUpdatesView()
            } label: {
                LabeledContent("Software") {
                    Text(status?.carVersions?.reportedVersion ?? "Not reported")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("vehicle-settings-software")
            if let update = status?.carVersions?.reportedUpdateVersion {
                LabeledContent("Update waiting", value: update)
            }
        } header: {
            Label("Software", systemImage: "shippingbox.fill")
        }
    }

    private var pickerSection: some View {
        Section {
            ForEach(environment.vehicles) { candidate in
                Button {
                    environment.selectVehicle(candidate)
                } label: {
                    HStack {
                        Text(candidate.name?.nilIfEmpty ?? "Vehicle \(candidate.id)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if candidate.id == vehicle?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(TessalyticsTheme.accent)
                        }
                    }
                    .contentShape(.rect)
                }
            }
        } header: {
            Label("Switch vehicle", systemImage: "arrow.left.arrow.right")
        }
    }

    private var coverageSection: some View {
        Section {
            LabeledContent("Drives recorded", value: (vehicle?.totalDrives ?? 0).formatted())
            LabeledContent("Charges recorded", value: (vehicle?.totalCharges ?? 0).formatted())
            LabeledContent("Updates recorded", value: (vehicle?.totalUpdates ?? 0).formatted())
        } header: {
            Label("On the server", systemImage: "externaldrive.fill")
        } footer: {
            Text("What TeslaMate holds for this car, which is not necessarily what has been synchronized to this iPhone.")
        }
    }
}
