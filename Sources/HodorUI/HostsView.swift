import HodorCore
import SwiftUI

/// The hosts page: each ssh host with its discovery state, suggestions from ~/.ssh/config, and a field to add one.
struct HostsView: View {
    var store: ProjectStore
    var discovery: [String: HostServers]
    /// Aliases from ~/.ssh/config. Those already added are not shown.
    var suggestions: [String]
    var onAdd: (String) -> Void

    @State private var newHost = ""
    /// A host used by projects that waits for a second click to be removed.
    @State private var confirmingRemoval: String?

    private var newSuggestions: [String] {
        suggestions.filter { !store.hosts.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.hosts.isEmpty {
                Text("No hosts yet. Projects need one to pick a dev server.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.hosts, id: \.self) { host in
                row(host)
                Divider()
            }

            if !newSuggestions.isEmpty {
                Text("From ~/.ssh/config").font(.caption).foregroundStyle(.secondary)
                ForEach(newSuggestions, id: \.self) { host in
                    HStack {
                        Text(host).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            onAdd(host)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Add \(host)")
                    }
                }
            }

            HStack {
                TextField(newSuggestions.isEmpty ? "ssh host or hostname" : "Other ssh host or hostname", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()
            Toggle("Show all listeners", isOn: Binding(get: { store.showAllServers }, set: { store.showAllServers = $0 }))
                .help("Also list other users' processes and servers outside git worktrees.")
        }
    }

    private func row(_ host: String) -> some View {
        let state = discovery[host]
        let users = store.projects.filter { $0.host == host }.count
        return HStack(alignment: .firstTextBaseline) {
            Circle().fill(dotColor(state)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(host).fontWeight(.semibold)
                if let error = state?.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.hodorWedge)
                        .textSelection(.enabled)
                } else {
                    Text(caption(state, users: users))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if confirmingRemoval == host {
                Button("Cancel") { confirmingRemoval = nil }
                Button("Remove", role: .destructive) {
                    confirmingRemoval = nil
                    store.removeHost(host)
                }
                .help("Its projects lose their server selection and stop.")
            } else {
                Button {
                    if users > 0 {
                        confirmingRemoval = host
                    } else {
                        store.removeHost(host)
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove \(host)")
            }
        }
    }

    private func dotColor(_ state: HostServers?) -> Color {
        guard let state, !state.isLoading else { return .secondary.opacity(0.4) }
        return state.error == nil ? .hodorNight : .hodorWedge
    }

    private func caption(_ state: HostServers?, users: Int) -> String {
        var parts: [String] = []
        if let state, !state.isLoading {
            let count = state.servers.filter { store.showAllServers || $0.isDevServer }.count
            parts.append(count == 1 ? "1 server" : "\(count) servers")
        } else {
            parts.append("Checking…")
        }
        if users > 0 {
            parts.append(users == 1 ? "used by 1 project" : "used by \(users) projects")
        }
        return parts.joined(separator: " · ")
    }

    private func add() {
        let host = newHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        onAdd(host)
        newHost = ""
    }
}
