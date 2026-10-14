import SwiftUI
import TunnelerCore

struct ContentView: View {
    @Bindable var store: ProjectStore
    var tunnels: TunnelManager

    @State private var servers: [DevServer] = []
    @State private var isLoading = false
    @State private var discoveryError: String?
    @State private var editing: Project?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let discoveryError {
                Text(discoveryError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.projects.isEmpty && !isAdding {
                Text("No projects yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach($store.projects) { $project in
                if editing?.id == project.id {
                    ProjectForm(project: project, onSave: { updated in
                        project = updated
                        editing = nil
                    }, onCancel: { editing = nil })
                } else {
                    ProjectRow(
                        project: $project,
                        servers: servers,
                        status: tunnels.status(for: project),
                        onToggle: { store.setActive($0, for: project.id) },
                        onEdit: { editing = project },
                        onDelete: { store.projects.removeAll { $0.id == project.id } }
                    )
                }
                Divider()
            }

            if isAdding {
                ProjectForm(project: nil, onSave: { project in
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
        .task { await refresh() }
    }

    private var header: some View {
        HStack {
            Text("Tunneler").font(.headline)
            Text(store.host).foregroundStyle(.secondary)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload dev servers from \(store.host)")
            .disabled(isLoading)
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            servers = try await DevServerDiscovery.discover(host: store.host)
            discoveryError = nil
        } catch {
            discoveryError = "Could not list servers on \(store.host): \(error.localizedDescription)"
        }
    }
}
