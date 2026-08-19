import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var presentedSheet: SettingsSheet?

    var body: some View {
        @Bindable var environment = environment
        NavigationStack {
            TessalyticsScreen {
                List {
                    Section {
                        Picker("Active server", selection: $environment.selectedProfile) {
                            ForEach(environment.profiles) { profile in Text(profile.name).tag(Optional(profile)) }
                        }
                        .onChange(of: environment.selectedProfile) { _, profile in
                            if let profile { Task { await environment.selectProfile(profile) } }
                        }
                        Button { presentedSheet = .addServer } label: {
                            Label("Add server", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Label("Server", systemImage: "server.rack")
                    } footer: {
                        Text("Server metadata is stored locally. Authentication credentials remain in Keychain.")
                    }

                    Section {
                        Picker("Active vehicle", selection: $environment.selectedVehicle) {
                            ForEach(environment.vehicles) { vehicle in
                                Text(vehicle.name ?? "Vehicle \(vehicle.id)").tag(Optional(vehicle))
                            }
                        }
                        .onChange(of: environment.selectedVehicle) { _, vehicle in
                            if let vehicle { environment.selectVehicle(vehicle) }
                        }
                    } header: {
                        Label("Vehicle", systemImage: "car.side.fill")
                    }

                    Section {
                        Button { presentedSheet = .ownerAPI } label: {
                            HStack {
                                Label("Direct Tesla", systemImage: "bolt.car.fill")
                                Spacer()
                                StatusBadge(
                                    text: environment.isOwnerConnected ? "Connected" : "Optional",
                                    color: environment.isOwnerConnected ? TessalyticsTheme.positive : TessalyticsTheme.steel
                                )
                            }
                        }
                        .accessibilityIdentifier("owner-api-settings")
                    } header: {
                        Label("Live data & controls", systemImage: "dot.radiowaves.left.and.right")
                    } footer: {
                        Text("Connect an Owner API token pair for live state and confirmed vehicle commands.")
                    }

                    Section("Privacy & support") {
                        Button { presentedSheet = .notifications } label: {
                            Label("Intelligence notifications", systemImage: "bell.badge.fill")
                        }
                        Button { presentedSheet = .software } label: {
                            Label("Software updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button { presentedSheet = .privacy } label: {
                            Label("Privacy", systemImage: "hand.raised.fill")
                        }
                        Button { presentedSheet = .about } label: {
                            Label("About Tessalytics", systemImage: "info.circle.fill")
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addServer:
                    AddServerView()
                case .notifications:
                    SettingsSheetContainer { IntelligenceNotificationSettingsView() }
                case .software:
                    SettingsSheetContainer { SoftwareUpdatesView() }
                case .privacy:
                    SettingsSheetContainer { PrivacyView() }
                case .about:
                    SettingsSheetContainer { AboutView() }
                case .ownerAPI:
                    OwnerAPIConnectionView()
                }
            }
        }
    }
}

private enum SettingsSheet: String, Identifiable {
    case addServer
    case notifications
    case software
    case privacy
    case about
    case ownerAPI

    var id: String { rawValue }
}

private struct SettingsSheetContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct AddServerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ProfileDraft()
    @State private var testing = false
    @State private var verified = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Server") { TextField("Profile name", text: $draft.name); TextField("https://example.com", text: $draft.serverURL).textInputAutocapitalization(.never).keyboardType(.URL); Toggle("Allow local HTTP", isOn: $draft.allowsLocalHTTP) }
                Section("Authentication") { Picker("Method", selection: $draft.authenticationMethod) { ForEach(AuthenticationMethod.allCases) { Text($0.title).tag($0) } }; if draft.authenticationMethod == .bearer { SecureField("Bearer token", text: $draft.token) }; if draft.authenticationMethod == .basic { TextField("Username", text: $draft.username); SecureField("Password", text: $draft.password) }; if draft.authenticationMethod == .none { Label("Use only on a trusted private network or VPN.", systemImage: "exclamationmark.triangle").foregroundStyle(TessalyticsTheme.warning) } }
                Section { Button(verified ? "Connection verified" : "Test Connection") { Task { await test() } }.disabled(testing); if let message { Text(message).foregroundStyle(verified ? TessalyticsTheme.positive : TessalyticsTheme.critical) } }
            }
            .scrollContentBackground(.hidden)
            .background { TessalyticsBackdrop() }
            .navigationTitle("Add server")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { try? await environment.saveProfile(draft); dismiss() } }.disabled(!verified) } }
        }
    }
    private func test() async { testing = true; defer { testing = false }; do { let profile = try draft.profile(); let result = try await TeslaMateAPIClient(baseURL: profile.baseURL, authentication: draft.credentials?.authentication ?? .none).testConnection(); verified = result.compatible; message = "Connected securely. \(result.vehicleCount) vehicle(s) found." } catch { verified = false; message = error.localizedDescription } }
}
