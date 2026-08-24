import SwiftUI

/// The browsers signed in to the web dashboard, and how to sign them out.
///
/// Granting access is worth nothing without a way to see and withdraw it, and a
/// dashboard left signed in on a car that has changed hands is exactly the case
/// this screen exists for. Revoking is immediate: the server drops the session, so
/// the next request that browser makes — including the live stream it is holding
/// open — is refused.
struct PairedBrowsersView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var sessions: [WebSessionSummary] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var isPairing = false

    var body: some View {
        List {
            if environment.selectedProfile == nil || environment.isDemoMode {
                Section {
                    Label(
                        environment.isDemoMode
                            ? "Demo mode has no server, so there is nothing signed in to it."
                            : "Connect your Tessalytics Backend to sign a browser in.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Button {
                        isPairing = true
                    } label: {
                        Label("Sign in a browser", systemImage: "qrcode.viewfinder")
                    }
                    .accessibilityIdentifier("paired-browsers-add")
                } footer: {
                    Text("""
                    Open the dashboard on the car's screen, then scan the code it shows. A paired browser gets \
                    read-only access; vehicle actions always need this app's server token.
                    """)
                }

                Section {
                    if isLoading && sessions.isEmpty {
                        ProgressView()
                    } else if sessions.isEmpty {
                        Text("No browsers are signed in.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            row(session)
                        }
                    }
                } header: {
                    Text("Signed in")
                } footer: {
                    // Worth saying plainly: it explains both a disappearing list
                    // and why nothing here is a long-term grant.
                    Text("Sessions live in the server's memory, so restarting the server signs every browser out.")
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(TessalyticsTheme.warning)
                    }
                }
            }
        }
        .navigationTitle("Paired browsers")
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $isPairing, onDismiss: { Task { await load() } }) {
            WebPairingSheet()
        }
        .accessibilityIdentifier("paired-browsers-screen")
    }

    private func row(_ session: WebSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.label).font(.body.weight(.semibold))
                Spacer()
                StatusBadge(text: session.scope == "read" ? "Read-only" : session.scope, color: TessalyticsTheme.steel)
            }
            if let address = session.address {
                Text(address).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let lastSeenAt = session.lastSeenAt {
                    Text(AppText.format("Last seen %@", lastSeenAt.formatted(.relative(presentation: .named))))
                }
                if let expiresAt = session.expiresAt {
                    Text(AppText.format("Expires %@", expiresAt.formatted(date: .abbreviated, time: .omitted)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await revoke(session) }
            } label: {
                Label("Revoke", systemImage: "xmark.circle")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await revoke(session) }
            } label: {
                Label("Revoke access", systemImage: "xmark.circle")
            }
        }
    }

    private func load() async {
        guard let profile = environment.selectedProfile, !environment.isDemoMode else {
            sessions = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await environment.backendClient(for: profile).webSessions()
            message = nil
        } catch {
            message = error.userFacingMessage
        }
    }

    private func revoke(_ session: WebSessionSummary) async {
        guard let profile = environment.selectedProfile else { return }
        do {
            try await environment.backendClient(for: profile).revokeWebSession(id: session.id)
            // Removed locally as well as remotely: re-reading the list is a round
            // trip the person watching does not need before seeing the effect.
            sessions.removeAll { $0.id == session.id }
            message = nil
        } catch {
            message = error.userFacingMessage
        }
    }
}
