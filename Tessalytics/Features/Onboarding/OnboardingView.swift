import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ProfileDraft()
    @State private var step = 0
    @State private var testing = false
    @State private var result: ConnectionTestResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            TessalyticsScreen {
                VStack(spacing: 0) {
                    OnboardingStepIndicator(step: step)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)

                    TabView(selection: $step) {
                        welcome.tag(0)
                        configuration.tag(1)
                        verification.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .tessalyticsReadableWidth(TessalyticsLayout.readableWidth)

                    navigationControls
                }
            }
            .navigationTitle("Tessalytics")
            .navigationBarTitleDisplayMode(.inline)
            // Back belongs in the leading toolbar slot, the same corner every
            // other screen in the app puts it in.
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityIdentifier("onboarding-back")
                    }
                }
            }
        }
        .accessibilityIdentifier("onboarding-screen")
    }

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 18) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(TessalyticsTheme.accent)
                        .frame(width: 92, height: 92)
                        .background(TessalyticsTheme.accent.opacity(0.10), in: .circle)
                        .overlay { Circle().strokeBorder(TessalyticsTheme.accent.opacity(0.18)) }
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Understand every drive.")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Connect TeslaMate, or explore instantly with generated sample data.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                SurfaceCard {
                    VStack(spacing: 18) {
                        OnboardingFeatureRow(
                            title: "Your server",
                            detail: "Your TeslaMate server stays under your control.",
                            symbol: "server.rack",
                            tint: TessalyticsTheme.neutral
                        )
                        Divider()
                        OnboardingFeatureRow(
                            title: "Direct and private",
                            detail: "Your iPhone connects straight to the server you choose.",
                            symbol: "lock.shield.fill",
                            tint: TessalyticsTheme.positive
                        )
                        Divider()
                        OnboardingFeatureRow(
                            title: "Controls stay optional",
                            detail: "Direct Tesla commands require Owner API tokens and device confirmation.",
                            symbol: "hand.raised.fill",
                            tint: TessalyticsTheme.warning
                        )
                    }
                }

                Link(destination: URL(string: "https://github.com/tobiasehlert/teslamateapi")!) {
                    Label("Tessalytics Backend setup guide", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var configuration: some View {
        Form {
            Section {
                Label {
                    TextField("Profile name", text: $draft.name)
                        .textContentType(.nickname)
                } icon: {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .foregroundStyle(TessalyticsTheme.accent)
                }

                Label {
                    TextField("https://example.com", text: $draft.serverURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(TessalyticsTheme.accent)
                }

                Toggle("Allow local HTTP development server", isOn: $draft.allowsLocalHTTP)
            } header: {
                Text("Server")
            } footer: {
                Text("HTTP is accepted only for localhost or common private-network addresses. TLS validation is never disabled.")
            }

            Section("Authentication") {
                Picker("Method", selection: $draft.authenticationMethod) {
                    ForEach(AuthenticationMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }

                switch draft.authenticationMethod {
                case .bearer:
                    SecureField("Bearer token", text: $draft.token)
                        .textContentType(.password)
                case .basic:
                    TextField("Username", text: $draft.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)
                case .none:
                    Label(
                        "Use only on a trusted private network or VPN. Anyone who can reach the server may be able to view location history.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(TessalyticsTheme.warning)
                }
            }

            Section {
                Button(action: beginConnectionTest) {
                    HStack {
                        if testing { ProgressView().controlSize(.small) }
                        Label(testing ? "Testing securely…" : "Test Connection", systemImage: "checkmark.shield.fill")
                        Spacer()
                    }
                }
                .disabled(testing)
                .accessibilityIdentifier("test-connection")
            } footer: {
                Text("Tessalytics checks reachability, authentication, and API compatibility. Credentials are kept only in Keychain.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var verification: some View {
        ScrollView {
            VStack(spacing: 22) {
                if testing {
                    LoadingPanel(title: "Testing your private connection", symbol: "checkmark.shield")
                } else if let result {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 58))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(TessalyticsTheme.positive)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("Connection verified")
                            .font(.title.bold())
                        Text("Tessalytics is ready to save this server securely.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    SurfaceCard(tint: TessalyticsTheme.positive) {
                        VStack(spacing: 14) {
                            VerificationCheck(label: "Server reachable", success: result.reachable)
                            VerificationCheck(label: "Authentication accepted", success: result.authenticated)
                            VerificationCheck(label: "Tessalytics Backend detected", success: result.compatible)
                            Divider()
                            Label("\(result.vehicleCount) vehicle\(result.vehicleCount == 1 ? "" : "s") found", systemImage: "car.2.fill")
                                .font(.headline)
                        }
                    }

                    Button(action: saveProfile) {
                        Label("Save Securely", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("save-profile")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Connection failed",
                        systemImage: "exclamationmark.icloud",
                        description: Text(errorMessage)
                    )
                    Button("Review settings", action: reviewSettings)
                        .buttonStyle(.bordered)
                }

                Text("If this fails, check that Tessalytics Backend is running and reachable from this iPhone, and that the token is correct.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var navigationControls: some View {
        VStack(spacing: 10) {
            if step == 0 {
                Button(action: environment.enterDemoMode) {
                    Label("Explore Demo", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens Tessalytics with generated sample vehicle data")
                .accessibilityIdentifier("explore-demo")

                Button(action: showConfiguration) {
                    Label("Configure server", systemImage: "server.rack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, step == 0 ? 14 : 0)
        .background(step == 0 ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
    }

    private func showConfiguration() {
        withAnimation(.smooth) { step = 1 }
    }

    private func goBack() {
        withAnimation(.smooth) { step = max(0, step - 1) }
    }

    private func reviewSettings() {
        withAnimation(.smooth) { step = 1 }
    }

    private func beginConnectionTest() {
        Task { await testConnection() }
    }

    private func saveProfile() {
        Task { await save() }
    }

    private func testConnection() async {
        testing = true
        errorMessage = nil
        result = nil

        do {
            let profile = try draft.profile()
            let outcome = try await ServerProbe.test(
                baseURL: profile.baseURL,
                authentication: draft.credentials?.authentication ?? .none
            )
            result = outcome
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        testing = false
        withAnimation(.smooth) { step = 2 }
    }

    private func save() async {
        do {
            try await environment.saveProfile(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OnboardingStepIndicator: View {
    let step: Int
    private let steps = [
        OnboardingStep(id: 0, title: "Welcome"),
        OnboardingStep(id: 1, title: "Server"),
        OnboardingStep(id: 2, title: "Verify")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps) { item in
                Capsule()
                    .fill(item.id <= step ? TessalyticsTheme.accent : Color.secondary.opacity(0.18))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(step + 1) of \(steps.count), \(steps[step].title)")
        .animation(.smooth, value: step)
    }
}

private struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
}

private struct OnboardingFeatureRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct VerificationCheck: View {
    let label: String
    let success: Bool

    var body: some View {
        Label(label, systemImage: success ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(success ? TessalyticsTheme.positive : TessalyticsTheme.critical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityValue(success ? "Passed" : "Failed")
    }
}
