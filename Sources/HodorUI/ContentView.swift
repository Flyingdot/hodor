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
    @State private var showHosts: Bool
    @State private var sshAliases: [String] = []

    public init(store: ProjectStore, tunnels: TunnelManager) {
        self.init(store: store, tunnels: tunnels, discovery: [:], discover: DevServerDiscovery.discover(host:))
    }

    /// Tests pass fixed discovery results and a stub instead of ssh.
    init(
        store: ProjectStore, tunnels: TunnelManager, discovery: [String: HostServers],
        discover: @escaping @Sendable (String) async throws -> [DevServer], showHosts: Bool = false
    ) {
        self.store = store
        self.tunnels = tunnels
        self.discover = discover
        _discovery = State(initialValue: discovery)
        _showHosts = State(initialValue: showHosts)
    }

    private var isLoading: Bool {
        discovery.values.contains { $0.isLoading }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if showHosts {
                HostsView(
                    store: store, discovery: discovery, suggestions: sshAliases,
                    onAdd: { host in
                        store.addHost(host)
                        Task { await refresh(host) }
                    })
            } else {
                projectList
            }
        }
        .padding()
        .frame(width: 420)
        .tint(.hodorNight)
        .task { await refreshAll() }
        // MenuBarExtra keeps the view alive between opens, so `.task` only runs once.
        // The popup becomes key each time it opens, and it's the app's only window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !isLoading else { return }
            Task { await refreshAll() }
        }
    }

    @ViewBuilder private var projectList: some View {
        ForEach(store.hosts, id: \.self) { host in
            if let error = discovery[host]?.error {
                Button {
                    openHosts()
                } label: {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.hodorWedge)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Show hosts")
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
                    showAllServers: store.showAllServers,
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

    private var header: some View {
        HStack {
            if showHosts {
                Button {
                    showHosts = false
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back to projects")
                Text("Hosts").font(.headline).fontDesign(.rounded)
            } else {
                HodorMark()
                Text("Hodor").font(.headline).fontDesign(.rounded)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
            if !showHosts {
                Button(action: openHosts) {
                    Image(systemName: "server.rack")
                }
                .buttonStyle(.borderless)
                .help("Manage hosts")
            }
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

    private func openHosts() {
        // Read on every visit, so newly added aliases show up.
        sshAliases = SSHConfig.hostAliases()
        showHosts = true
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
