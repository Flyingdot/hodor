import HodorCore
import SwiftUI

/// Discovery result for one host.
struct HostServers {
    var servers: [DevServer] = []
    var error: String?
    var isLoading = false
}

public struct ContentView: View {
    @Bindable var store: ProjectStore
    var tunnels: TunnelManager
    private let discover: @Sendable (String) async throws -> [DevServer]

    @State private var discovery: [String: HostServers]
    @State private var editing: Project?
    @State private var isAdding = false
    @State private var showHosts = false

    public init(store: ProjectStore, tunnels: TunnelManager) {
        self.init(store: store, tunnels: tunnels, discovery: [:], discover: DevServerDiscovery.discover(host:))
    }

    /// Tests pass fixed discovery results and a stub instead of ssh.
    init(
        store: ProjectStore, tunnels: TunnelManager, discovery: [String: HostServers],
        discover: @escaping @Sendable (String) async throws -> [DevServer]
    ) {
        self.store = store
        self.tunnels = tunnels
        self.discover = discover
        _discovery = State(initialValue: discovery)
    }

    private var isLoading: Bool {
        discovery.values.contains { $0.isLoading }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if showHosts {
                HostsView(
                    store: store, discovery: discovery,
                    onAdd: { host in
                        store.addHost(host)
                        Task { await refresh(host) }
                    })
                Divider()
            } else {
                ForEach(store.hosts, id: \.self) { host in
                    if let error = discovery[host]?.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }

            if store.projects.isEmpty && !isAdding {
                Text("No projects yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach($store.projects) { $project in
                if editing?.id == project.id {
                    ProjectForm(
                        project: project,
                        onSave: { updated in
                            project = updated
                            editing = nil
                        }, onCancel: { editing = nil })
                } else {
                    ProjectRow(
                        project: $project,
                        hosts: store.hosts,
                        discovery: discovery,
                        status: tunnels.status(for: project),
                        onToggle: { store.setActive($0, for: project.id) },
                        onEdit: { editing = project },
                        onDelete: { store.projects.removeAll { $0.id == project.id } }
                    )
                }
                Divider()
            }

            if isAdding {
                ProjectForm(
                    project: nil,
                    onSave: { project in
                        store.projects.append(project)
                        isAdding = false
                    }, onCancel: { isAdding = false })
            }

            HStack {
                Button("Add Project", systemImage: "plus") { isAdding = true }
                    .disabled(isAdding)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 420)
        .task { await refreshAll() }
    }

    private var header: some View {
        HStack {
            Text("Hodor").font(.headline)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                showHosts.toggle()
            } label: {
                Image(systemName: showHosts ? "server.rack.fill" : "server.rack")
            }
            .buttonStyle(.borderless)
            .help("Hosts")
            Button {
                Task { await refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload dev servers from all hosts")
            .disabled(isLoading)
        }
    }

    /// Queries all hosts in parallel; a slow or unreachable host doesn't hold up the others.
    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for host in store.hosts {
                group.addTask { await refresh(host) }
            }
        }
    }

    private func refresh(_ host: String) async {
        discovery[host, default: HostServers()].isLoading = true
        do {
            let servers = try await discover(host)
            discovery[host] = HostServers(servers: servers)
        } catch {
            discovery[host] = HostServers(servers: [], error: error.localizedDescription)
        }
    }
}
