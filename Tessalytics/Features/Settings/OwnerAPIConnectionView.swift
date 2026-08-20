import SwiftUI

struct OwnerAPIConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var region = OwnerAPIRegion.global
    @State private var isConnecting = false
    @State private var message: String?
    @State private var showDisconnectConfirmation = false

    var body: some View {
        @Bindable var environment = environment
        NavigationStack {
            Form {
                if environment.isOwnerConnected {
                    connectedContent(environment: environment)
                } else {
                    connectionForm
                }
            }
            .scrollContentBackground(.hidden)
            .background { TessalyticsBackdrop() }
            .navigationTitle("Direct Tesla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { TessalyticsDismissButton() }
            }
            .confirmationDialog("Disconnect Direct Tesla?", isPresented: $showDisconnectConfirmation) {
                Button("Disconnect", role: .destructive) {
                    Task { await environment.disconnectOwnerAPI() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The Owner API tokens will be removed from this iPhone.")
            }
        }
        .accessibilityIdentifier("owner-api-connection-screen")
    }

    @ViewBuilder
    private func connectedContent(environment: AppEnvironment) -> some View {
        Section {
            LabeledContent("Status") {
                StatusBadge(text: "Connected", color: TessalyticsTheme.positive)
            }
            if !environment.ownerVehicles.isEmpty {
                Picker("Control vehicle", selection: Binding(
                    get: { environment.selectedOwnerVehicle },
                    set: { vehicle in
                        guard let vehicle else { return }
                        Task { await environment.selectOwnerVehicle(vehicle) }
                    }
                )) {
                    ForEach(environment.ownerVehicles) { vehicle in
                        Text(vehicle.displayName ?? vehicle.vin).tag(Optional(vehicle))
                    }
                }
            }
        } header: {
            Label("Owner API", systemImage: "bolt.car.fill")
        } footer: {
            Text("Live state and confirmed commands use the selected vehicle. TeslaMate remains the history source.")
        }

        if let error = environment.ownerLastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(TessalyticsTheme.warning)
            }
        }

        Section {
            Button {
                Task { await environment.refreshOwnerVehicles() }
            } label: {
                Label("Refresh live connection", systemImage: "arrow.clockwise")
            }
            Button("Disconnect", role: .destructive) {
                showDisconnectConfirmation = true
            }
        }
    }

    private var connectionForm: some View {
        Group {
            Section {
                Picker("Region", selection: $region) {
                    ForEach(OwnerAPIRegion.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Owner API", systemImage: "globe")
            }

            Section {
                SecureField("Access token", text: $accessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("owner-access-token")
                PasteButton(payloadType: String.self) { values in
                    accessToken = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                .accessibilityLabel("Paste access token")
            } header: {
                Text("Access token")
            }

            Section {
                SecureField("Refresh token", text: $refreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("owner-refresh-token")
                PasteButton(payloadType: String.self) { values in
                    refreshToken = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                .accessibilityLabel("Paste refresh token")
            } header: {
                Text("Refresh token")
            } footer: {
                Text("Generate the Owners API pair in Auth for Tesla. Never enter your Tesla password here. Tokens stay in this iPhone's Keychain.")
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isConnecting { ProgressView().controlSize(.small) }
                        Label(isConnecting ? "Connecting…" : "Connect", systemImage: "key.horizontal.fill")
                    }
                }
                .disabled(isConnecting || accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connect-owner-api")

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(TessalyticsTheme.critical)
                }
            } footer: {
                Text("Owner API is unofficial and may change without notice.")
            }
        }
    }

    private func connect() async {
        isConnecting = true
        message = nil
        defer { isConnecting = false }
        do {
            try await environment.connectOwnerAPI(accessToken: accessToken, refreshToken: refreshToken, region: region)
            accessToken = ""
            refreshToken = ""
        } catch {
            message = error.localizedDescription
        }
    }
}
