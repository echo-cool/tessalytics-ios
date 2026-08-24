import SwiftUI

struct SettingsView: View {
    @Environment(\.locale) private var locale
    @Environment(AppEnvironment.self) private var environment
    @State private var presentedSheet: SettingsSheet?
    @State private var confirmsDemo = false
    @State private var profilePendingRemoval: ServerProfile?
    @State private var editingProfile: ServerProfile?
    @State private var confirmsResync = false
    @State private var confirmsErase = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Taps on the version number so far, and when the last one landed.
    ///
    /// A run rather than a count: five taps spread over an afternoon are five
    /// people reading the version number, not one person asking for the debug
    /// screens.
    @State private var versionTaps = 0
    @State private var versionTapsStartedAt: Date?
    @State private var showsUnlockConfirmation = false

    var body: some View {
        @Bindable var environment = environment
        NavigationStack {
            TessalyticsScreen {
                List {
                    if environment.isDemoMode {
                        Section {
                            HStack {
                                Label("Generated sample data", systemImage: "sparkles")
                                Spacer()
                                StatusBadge(text: "Demo", color: TessalyticsTheme.accent)
                            }
                            Button { presentedSheet = .addServer } label: {
                                Label("Connect a real server", systemImage: "server.rack")
                            }
                            .accessibilityIdentifier("connect-real-server")
                            Button {
                                Task { await environment.leaveDemoMode() }
                            } label: {
                                Label("Leave demo", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .accessibilityIdentifier("leave-demo")
                        } header: {
                            Label("Demo experience", systemImage: "play.circle.fill")
                        } footer: {
                            Text("All visible vehicle and activity information is generated on this device.")
                        }

                        Section {
                            // Developer-only here too — see the note on the other
                            // copy of this row, further down.
                            if environment.diagnostics.isUnlocked {
                                Button { presentedSheet = .ownerAPI } label: {
                                    HStack {
                                        Label("Direct Tesla", systemImage: "bolt.car.fill")
                                        Spacer()
                                        StatusBadge(text: "Developer", color: TessalyticsTheme.warning)
                                    }
                                }
                                .accessibilityIdentifier("owner-api-settings")
                            }
                            Button { presentedSheet = .liveCharts } label: {
                                Label("Live charts", systemImage: "chart.xyaxis.line")
                            }
                            .accessibilityIdentifier("live-charts-settings")
                        } header: {
                            Label("Live data", systemImage: "dot.radiowaves.left.and.right")
                        } footer: {
                            Text("Charts of the live stream. Generated demo data feeds them here.")
                        }
                    } else {
                        ServerListSection(editing: $editingProfile) {
                            presentedSheet = .addServer
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
                            Button { presentedSheet = .specification } label: {
                                Label("Vehicle rating", systemImage: "gauge.with.dots.needle.67percent")
                            }
                            .accessibilityIdentifier("vehicle-specification")
                        } header: {
                            Label("Vehicle", systemImage: "car.side.fill")
                        } footer: {
                            Text("Set the capacity and range your car was rated at when new.")
                        }

                        Section {
                            // The Owner API is unofficial, undocumented and
                            // retired in pieces by Tesla without notice — the
                            // vehicles endpoint has answered 412 since 2023. It
                            // stays in the app for people working on it, behind
                            // the same unlock as the rest of the debug tools,
                            // rather than being offered to owners as a feature
                            // that may stop working under them.
                            if environment.diagnostics.isUnlocked {
                                Button { presentedSheet = .ownerAPI } label: {
                                    HStack {
                                        Label("Direct Tesla", systemImage: "bolt.car.fill")
                                        Spacer()
                                        StatusBadge(
                                            text: environment.isOwnerConnected ? "Connected" : "Developer",
                                            color: environment.isOwnerConnected ? TessalyticsTheme.positive : TessalyticsTheme.warning
                                        )
                                    }
                                }
                                .accessibilityIdentifier("owner-api-settings")
                            }
                            Button { presentedSheet = .liveCharts } label: {
                                Label("Live charts", systemImage: "chart.xyaxis.line")
                            }
                            .accessibilityIdentifier("live-charts-settings")
                            Button { presentedSheet = .pairedBrowsers } label: {
                                Label("Paired browsers", systemImage: "qrcode.viewfinder")
                            }
                            .accessibilityIdentifier("paired-browsers-settings")
                        } header: {
                            Label("Live data & controls", systemImage: "dot.radiowaves.left.and.right")
                        } footer: {
                            Text("Connect an Owner API token pair for live state and confirmed vehicle commands. Paired browsers are the read-only web sessions this phone has signed in.")
                        }

                        Section {
                            Button { confirmsDemo = true } label: {
                                Label("Explore demo data", systemImage: "play.circle.fill")
                            }
                            .accessibilityIdentifier("enter-demo-settings")
                        } footer: {
                            Text("Your configured servers remain saved while you explore generated sample data.")
                        }

                        Section {
                            Button {
                                confirmsResync = true
                            } label: {
                                Label("Re-sync history", systemImage: "arrow.clockwise.circle")
                            }
                            .accessibilityIdentifier("resync-history")

                            Button(role: .destructive) {
                                confirmsErase = true
                            } label: {
                                Label("Erase all data and start over", systemImage: "exclamationmark.triangle")
                            }
                            .accessibilityIdentifier("erase-everything")
                        } header: {
                            Label("Manage data", systemImage: "externaldrive")
                        } footer: {
                            Text("Affects this iPhone only. Your TeslaMate server keeps everything.")
                        }
                        .disabled(isWorking)
                    }

                    // Outside the demo/real branch on purpose: someone exploring
                    // the demo in Chinese should not have to configure a server
                    // before the app will speak to them in it.
                    Section {
                        Picker(selection: $environment.language) {
                            ForEach(AppLanguage.allCases) { option in
                                Text(locale.appString(option.title)).tag(option)
                            }
                        } label: {
                            Label("Language", systemImage: "globe")
                        }
                        .accessibilityIdentifier("language-picker")
                    } header: {
                        Label("Language", systemImage: "character.bubble")
                    } footer: {
                        Text("Applies to Tessalytics only, and takes effect straight away. Dates, distances and numbers keep following your region settings.")
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
                        Button { presentedSheet = .achievements } label: {
                            Label("Achievements", systemImage: "trophy.fill")
                        }
                        .accessibilityIdentifier("settings-achievements")
                        Button { presentedSheet = .about } label: {
                            Label("About Tessalytics", systemImage: "info.circle.fill")
                        }
                    }
                    .foregroundStyle(.primary)

                    versionSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .confirmationDialog("Explore generated demo data?", isPresented: $confirmsDemo) {
                Button("Explore Demo") { environment.enterDemoMode() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your existing server settings and credentials will remain saved.")
            }
            // Keyed on the profile so the dialog can name what is being removed:
            // "Remove" with no subject is how the wrong server gets deleted.
            .confirmationDialog(
                profilePendingRemoval.map { "Remove \($0.name)?" } ?? "Remove server?",
                isPresented: Binding(
                    get: { profilePendingRemoval != nil },
                    set: { if !$0 { profilePendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let profile = profilePendingRemoval {
                    Button("Remove Server", role: .destructive) {
                        perform { try await environment.deleteProfile(profile) }
                    }
                }
                Button("Cancel", role: .cancel) { profilePendingRemoval = nil }
            } message: {
                Text("Deletes this server's synchronized history and credentials from this iPhone.")
            }
            .confirmationDialog("Re-sync history?", isPresented: $confirmsResync, titleVisibility: .visible) {
                Button("Re-sync") { perform { await environment.resyncFromScratch() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears the cached history and downloads it again. The server stays configured.")
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmsErase, titleVisibility: .visible) {
                Button("Erase Everything", role: .destructive) {
                    perform { await environment.eraseEverything() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every server, all history, and all stored tokens. This cannot be undone.")
            }
            .alert("Debug mode is on", isPresented: $showsUnlockConfirmation) {
                Button("Open") { presentedSheet = .diagnostics }
                Button("Later", role: .cancel) {}
            } message: {
                Text("A Debug section is now at the bottom of Settings. Turn it off from there when you are finished.")
            }
            .alert(
                "Could not complete",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .overlay {
                if isWorking {
                    ProgressView().controlSize(.large).padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .sheet(item: $editingProfile) { profile in
                SettingsSheetContainer { EditServerView(profile: profile) }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addServer:
                    AddServerView()
                case .specification:
                    SettingsSheetContainer { VehicleSpecificationView() }
                case .notifications:
                    SettingsSheetContainer { IntelligenceNotificationSettingsView() }
                case .software:
                    SettingsSheetContainer { SoftwareUpdatesView() }
                case .liveCharts:
                    SettingsSheetContainer { LiveChartSettingsView() }
                case .privacy:
                    SettingsSheetContainer { PrivacyView() }
                case .about:
                    SettingsSheetContainer { AboutView() }
                case .ownerAPI:
                    OwnerAPIConnectionView()
                case .diagnostics:
                    SettingsSheetContainer { DiagnosticsView() }
                case .achievements:
                    SettingsSheetContainer { AchievementsView() }
                case .pairedBrowsers:
                    SettingsSheetContainer { PairedBrowsersView() }
                }
            }
        }
    }
}

private extension SettingsView {
    /// Runs a destructive action with a spinner, surfacing any failure.
    ///
    /// A silent failure here is the worst outcome: the user believes their data
    /// is gone when it is not.
    func perform(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            profilePendingRemoval = nil
        }
    }
}

private extension SettingsView {
    /// The version number, and the way in.
    ///
    /// Five taps rather than a switch in a menu, because this is a hatch for the
    /// one person a year who is chasing something — not a feature. The count is
    /// deliberately not shown until it is nearly there, so a stray double tap on
    /// a footer does not read as the app doing something.
    @ViewBuilder var versionSection: some View {
        Section {
            Button {
                registerVersionTap()
            } label: {
                HStack {
                    Label("Version", systemImage: "number")
                    Spacer()
                    Text(Diagnostics.appVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-version")
            .accessibilityHint("Tap five times to turn on debug mode")

            if environment.diagnostics.isUnlocked {
                Button { presentedSheet = .diagnostics } label: {
                    Label("Debug", systemImage: "ladybug.fill")
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("settings-diagnostics")
            }
        } footer: {
            if let remaining = remainingTapsToUnlock {
                Text("\(remaining) more \(remaining == 1 ? "tap" : "taps") to turn on debug mode.")
            }
        }
    }

    /// How many taps are left, once a reader is close enough for the hint to be
    /// an answer rather than a distraction.
    var remainingTapsToUnlock: Int? {
        guard !environment.diagnostics.isUnlocked else { return nil }
        let remaining = Diagnostics.tapsToUnlock - versionTaps
        return (1...2).contains(remaining) ? remaining : nil
    }

    /// How long a run of taps stays open **between taps**.
    ///
    /// Measured from the previous tap rather than from the first, and generous
    /// with it. A three-second budget for the whole run assumed five quick taps
    /// on a short list; the Settings list has grown, and a slower device — or a
    /// slower hand — spends longer than that getting through five without having
    /// given up. Restarting the count on someone mid-run is the one failure this
    /// gesture must not have, because nothing on screen explains it.
    static var versionTapWindow: TimeInterval { 5 }

    func registerVersionTap() {
        guard !environment.diagnostics.isUnlocked else {
            presentedSheet = .diagnostics
            return
        }
        let now = Date.now
        if let previous = versionTapsStartedAt, now.timeIntervalSince(previous) > Self.versionTapWindow {
            versionTaps = 0
        }
        versionTapsStartedAt = now
        versionTaps += 1
        guard versionTaps >= Diagnostics.tapsToUnlock else { return }
        versionTaps = 0
        versionTapsStartedAt = nil
        environment.diagnostics.unlock()
        showsUnlockConfirmation = true
    }
}

private enum SettingsSheet: String, Identifiable {
    case addServer
    case specification
    case notifications
    case software
    case liveCharts
    case privacy
    case about
    case ownerAPI
    case diagnostics
    case achievements
    case pairedBrowsers

    var id: String { rawValue }
}

struct SettingsSheetContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { TessalyticsDismissButton() }
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
                Section {
                    TextField("Profile name", text: $draft.name)
                    TextField("https://example.com", text: $draft.serverURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    Toggle("Allow insecure HTTP", isOn: $draft.allowsLocalHTTP)
                } header: {
                    Text("Tessalytics Backend")
                } footer: {
                    Text("The address of Tessalytics Backend, deployed beside TeslaMate. Use HTTPS on public networks. Enabling HTTP allows a public IP and port too, but sends the credential and vehicle data without encryption.")
                }
                Section("Authentication") { Picker("Method", selection: $draft.authenticationMethod) { ForEach(AuthenticationMethod.allCases) { Text($0.title).tag($0) } }; if draft.authenticationMethod == .bearer { SecureField("Bearer token", text: $draft.token) }; if draft.authenticationMethod == .basic { TextField("Username", text: $draft.username); SecureField("Password", text: $draft.password) }; if draft.authenticationMethod == .none { Label("Use only on a trusted private network or VPN.", systemImage: "exclamationmark.triangle").foregroundStyle(TessalyticsTheme.warning) } }
                Section { Button(verified ? "Connection verified" : "Test Connection") { Task { await test() } }.disabled(testing); if let message { Text(message).foregroundStyle(verified ? TessalyticsTheme.positive : TessalyticsTheme.critical) } }
            }
            .scrollContentBackground(.hidden)
            .background { TessalyticsBackdrop() }
            .navigationTitle("Add server")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { try? await environment.saveProfile(draft); dismiss() } }.disabled(!verified) } }
        }
    }
    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let profile = try draft.profile()
            let result = try await ServerProbe.test(
                baseURL: profile.baseURL,
                authentication: draft.credentials?.authentication ?? .none
            )
            verified = result.compatible
            message = "Connected. \(result.vehicleCount) vehicle(s) found."
        } catch {
            verified = false
            message = error.localizedDescription
        }
    }
}
