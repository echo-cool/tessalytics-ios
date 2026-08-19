import SwiftUI

struct DirectTeslaControlsCard: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pendingCommand: OwnerVehicleCommand?
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        SectionCard(
            "Direct controls",
            subtitle: environment.selectedOwnerVehicle?.displayName ?? "Owner API",
            symbol: "bolt.car.fill",
            tint: TessalyticsTheme.accent
        ) {
            LazyVGrid(columns: columns, spacing: 8) {
                commandButton(environment.status?.carStatus?.locked == true ? .unlock : .lock)
                commandButton(environment.status?.climateDetails?.isClimateOn == true ? .climateOff : .climateOn)
                commandButton(environment.status?.chargingDetails?.chargingState?.lowercased() == "charging" ? .chargeStop : .chargeStart)
                commandButton(.openTrunk)
            }

            if environment.isOwnerCommandRunning {
                ProgressView("Sending securely…")
                    .font(.caption)
            } else if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(TessalyticsTheme.positive)
            } else if let error = environment.ownerLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(TessalyticsTheme.warning)
            }
        }
        .confirmationDialog(
            pendingCommand.map { "Send \($0.title.lowercased())?" } ?? "Send command?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingCommand {
                Button(pendingCommand.title, role: pendingCommand == .unlock ? .destructive : nil) {
                    Task { await authorizeAndSend(pendingCommand) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tessalytics will ask for Face ID or the device passcode before contacting the vehicle.")
        }
        .alert("Command failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The command could not be completed.")
        }
        .accessibilityIdentifier("direct-tesla-controls")
    }

    private func commandButton(_ command: OwnerVehicleCommand) -> some View {
        Button {
            pendingCommand = command
            showConfirmation = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: command.symbol)
                    .font(.headline)
                Text(command.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(TessalyticsTheme.accent.opacity(0.09), in: .rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(environment.isOwnerCommandRunning)
        .accessibilityIdentifier("owner-command-\(command.rawValue)")
    }

    private func authorizeAndSend(_ command: OwnerVehicleCommand) async {
        resultMessage = nil
        guard await OwnerCommandAuthorization.request(for: command) else { return }
        do {
            try await environment.performOwnerCommand(command)
            resultMessage = "\(command.title) completed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
