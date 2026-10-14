import SwiftUI
import HodorCore

/// Lists the ssh hosts with their discovery state, and adds or removes hosts.
struct HostsView: View {
    var store: ProjectStore
    var discovery: [String: HostServers]
    var onAdd: (String) -> Void

    @State private var newHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hosts").font(.subheadline).foregroundStyle(.secondary)

            ForEach(store.hosts, id: \.self) { host in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host)
                        if let state = discovery[host] {
                            if let error = state.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            } else if !state.isLoading {
                                Text(state.servers.count == 1 ? "1 server" : "\(state.servers.count) servers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        store.removeHost(host)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(host). Projects using it lose their server selection.")
                }
            }

            HStack {
                TextField("ssh host, e.g. castle-black", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let host = newHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        onAdd(host)
        newHost = ""
    }
}
