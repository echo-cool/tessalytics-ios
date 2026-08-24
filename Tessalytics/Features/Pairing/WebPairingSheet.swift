import SwiftUI

/// Signing a browser in to the web dashboard.
///
/// Scan, check, approve. The checking step is the reason this is a sheet and not a
/// single tap: a QR code can come from anywhere, and the only thing standing
/// between a stranger's code and a stranger reading this car's location history is
/// somebody looking at what they are about to approve. So the sheet shows the code
/// to compare against the screen, the address the request arrived at, the browser
/// that made it, and where it came from — and then asks for Face ID.
///
/// What is granted is read-only. That is stated on the sheet, because "sign this
/// browser in" otherwise sounds like it might not be.
struct WebPairingSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var manualCode = ""
    @State private var cameraMessage: String?

    private enum Phase: Equatable {
        case scanning
        case manual
        case loading
        case confirm(WebPairingRequest)
        case approving(WebPairingRequest)
        case approved(WebSessionSummary)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Sign in a browser")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    if case .scanning = phase {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Enter code") { phase = .manual }
                                .accessibilityIdentifier("pairing-manual-entry")
                        }
                    }
                }
        }
        .accessibilityIdentifier("web-pairing-sheet")
    }

    @ViewBuilder private var content: some View {
        if environment.isDemoMode || environment.selectedProfile == nil {
            unavailable
        } else {
            switch phase {
            case .scanning:
                scanner
            case .manual:
                manualEntry
            case .loading:
                ProgressView("Reading the pairing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .confirm(let request):
                confirmation(request, isWorking: false)
            case .approving(let request):
                confirmation(request, isWorking: true)
            case .approved(let session):
                approved(session)
            case .failed(let message):
                failure(message)
            }
        }
    }

    // MARK: - States

    private var unavailable: some View {
        VStack(spacing: 16) {
            EmptyState(
                title: "No server connected",
                message: environment.isDemoMode
                    ? "Demo mode has no server to sign a browser in to. Connect your Tessalytics Backend first."
                    : "Add your Tessalytics Backend in Settings, then come back to sign a browser in.",
                symbol: "qrcode.viewfinder"
            )
        }
        .padding()
    }

    private var scanner: some View {
        ZStack {
            QRScannerView(
                onScan: handle(payload:),
                onUnavailable: { message in
                    cameraMessage = message
                    phase = .manual
                }
            )
            .ignoresSafeArea(edges: .bottom)
            ScannerReticle()
            VStack {
                Spacer()
                Text("Open the dashboard in the car's browser, then point the camera at the code on screen.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(20)
            }
        }
    }

    private var manualEntry: some View {
        Form {
            if let cameraMessage {
                Section {
                    Label(cameraMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(TessalyticsTheme.warning)
                }
            }
            Section {
                TextField("ABCD-EFGH", text: $manualCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title2, design: .monospaced))
                    .accessibilityIdentifier("pairing-code-field")
            } header: {
                Text("Pairing code")
            } footer: {
                Text("The code printed beside the QR symbol on the dashboard.")
            }

            Section {
                Button("Find pairing") {
                    Task { await lookUp(code: manualCode) }
                }
                .disabled(WebPairingCode.normalisedCode(manualCode) == nil)
                if AVCaptureDeviceAvailability.hasCamera {
                    Button("Scan instead") {
                        cameraMessage = nil
                        phase = .scanning
                    }
                }
            }
        }
    }

    private func confirmation(_ request: WebPairingRequest, isWorking: Bool) -> some View {
        Form {
            Section {
                Text(request.code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("pairing-code-display")
            } header: {
                Text("Check this matches the screen")
            } footer: {
                // The one instruction on this sheet that actually protects anything.
                Text("If these do not match, the code did not come from your dashboard. Deny it.")
            }

            Section("Requested by") {
                LabeledContent("Browser", value: request.browser)
                if let address = request.address {
                    LabeledContent("Address", value: address)
                }
                if let origin = request.origin {
                    LabeledContent("Page", value: origin)
                }
                if let seconds = request.expiresInSeconds {
                    LabeledContent("Expires in", value: "\(max(seconds, 0))s")
                }
            }

            Section {
                Button {
                    Task { await approve(request) }
                } label: {
                    Label("Approve read-only access", systemImage: "checkmark.shield.fill")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("pairing-approve")

                Button(role: .destructive) {
                    Task { await deny(request) }
                } label: {
                    Label("Deny", systemImage: "xmark.shield")
                }
                .disabled(isWorking)
            } footer: {
                Text("""
                The browser will be able to read this vehicle's live state and history. It cannot lock, unlock, \
                wake or command the car — vehicle actions need this app's server token, and the server refuses \
                them to a paired browser. You can revoke access at any time in Settings → Paired browsers.
                """)
            }

            if isWorking {
                Section { ProgressView("Approving…") }
            }
        }
    }

    private func approved(_ session: WebSessionSummary) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(TessalyticsTheme.positive)
            Text(AppText.format("%@ is signed in", session.label))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let expiresAt = session.expiresAt {
                Text(AppText.format("Read-only access until %@.", expiresAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("The dashboard should be showing your vehicle within a couple of seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("pairing-done")
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(TessalyticsTheme.warning)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") {
                cameraMessage = nil
                phase = AVCaptureDeviceAvailability.hasCamera ? .scanning : .manual
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handle(payload: String) {
        guard let scanned = WebPairingCode(scanned: payload) else {
            phase = .failed("That code is not a Tessalytics pairing code. Open the dashboard in the car's browser and scan the code it shows.")
            return
        }
        Task { await load(scanned) }
    }

    private func load(_ scanned: WebPairingCode) async {
        phase = .loading
        do {
            let request = try await client().pairingRequest(id: scanned.pairingID)
            guard request.isPending else {
                phase = .failed("That pairing is no longer waiting — it was already \(request.status). Reload the dashboard for a new code.")
                return
            }
            guard request.code == scanned.code else {
                // The server and the symbol disagree about which code this is,
                // which is not something a working flow does.
                phase = .failed("That code does not match the pairing on the server. Reload the dashboard and scan again.")
                return
            }
            phase = .confirm(request)
        } catch {
            phase = .failed(error.userFacingMessage)
        }
    }

    private func lookUp(code: String) async {
        guard let normalised = WebPairingCode.normalisedCode(code) else { return }
        phase = .loading
        do {
            let request = try await client().findPairing(code: normalised)
            phase = .confirm(request)
        } catch {
            phase = .failed(error.userFacingMessage)
        }
    }

    private func approve(_ request: WebPairingRequest) async {
        guard await WebPairingAuthorization.request(browser: request.browser) else { return }
        phase = .approving(request)
        do {
            let session = try await client().approvePairing(
                id: request.pairingID,
                code: request.code,
                label: request.browser
            )
            phase = .approved(session)
        } catch {
            phase = .failed(error.userFacingMessage)
        }
    }

    private func deny(_ request: WebPairingRequest) async {
        do {
            try await client().denyPairing(id: request.pairingID)
            dismiss()
        } catch {
            phase = .failed(error.userFacingMessage)
        }
    }

    private func client() throws -> TessalyticsBackendClient {
        guard let profile = environment.selectedProfile else { throw ClientError.invalidConfiguration }
        return try environment.backendClient(for: profile)
    }
}

/// Whether this device has a camera at all.
///
/// Its own type so the views can ask without importing AVFoundation, and so the
/// simulator — which has none — lands on the manual path rather than on a black
/// rectangle.
enum AVCaptureDeviceAvailability {
    static var hasCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
