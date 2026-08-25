import SwiftUI

/// The configured servers, with somewhere to rename or remove one.
///
/// Adding was the only thing the settings screen could do to a server: renaming
/// was impossible and removal was buried in a data-management section, which put
/// a destructive action next to "erase everything" and gave a mistyped name no
/// remedy at all.
struct ServerListSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var editing: ServerProfile?
    let onAdd: () -> Void

    var body: some View {
        Section {
            ForEach(environment.profiles) { profile in
                Button {
                    editing = profile
                } label: {
                    ServerRow(
                        profile: profile,
                        isActive: environment.selectedProfile?.id == profile.id
                    )
                }
                .accessibilityIdentifier("server-row-\(profile.id.uuidString)")
            }
            Button(action: onAdd) {
                Label("Add server", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("add-server")
        } header: {
            Label("Servers", systemImage: "server.rack")
        } footer: {
            Text("Tap a server to rename it, switch to it, or remove it.")
        }
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? TessalyticsTheme.positive : TessalyticsTheme.steel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(profile.baseURL.host() ?? profile.baseURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.name)
        .accessibilityValue(isActive ? "Active server" : "Not active")
    }
}

/// Rename, activate or remove one server.
struct EditServerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let profile: ServerProfile

    @State private var name = ""
    @State private var confirmsRemoval = false
    @State private var working = false
    @State private var message: String?

    private var isActive: Bool { environment.selectedProfile?.id == profile.id }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != profile.name }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("server-name-field")
            } header: {
                Text("Name")
            } footer: {
                Text("A label for this iPhone only. The server is not contacted.")
            }

            Section("Address") {
                LabeledContent("URL", value: profile.baseURL.absoluteString)
                    .textSelection(.enabled)
                LabeledContent("Authentication", value: profile.authenticationMethod.title)
            }

            if !isActive {
                Section {
                    Button {
                        perform { await environment.selectProfile(profile) }
                    } label: {
                        Label("Make active", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("activate-server")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmsRemoval = true
                } label: {
                    Label("Remove this server", systemImage: "trash")
                }
                .accessibilityIdentifier("remove-server")
            } footer: {
                Text("Removes the local copy only. Your server keeps everything.")
            }

            if let message {
                Section { Text(message).foregroundStyle(TessalyticsTheme.critical) }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try environment.renameProfile(profile, to: trimmed)
                        dismiss()
                    } catch {
                        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
                .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "Remove \(profile.name)?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove server", role: .destructive) {
                perform { try? await environment.deleteProfile(profile) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its synchronized data and credentials are deleted from this iPhone.")
        }
        .task {
            if name.isEmpty { name = profile.name }
        }
    }

    private func perform(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
            dismiss()
        }
    }
}
