import HodorCore
import SwiftUI

struct ProjectRow: View {
    @Binding var project: Project
    var hosts: [String]
    var discovery: [String: HostServers]
    var status: TunnelStatus
    var onToggle: @MainActor @Sendable (Bool) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).fontWeight(.semibold)
                    if let url = URL(string: project.url) {
                        Link(project.url, destination: url).font(.caption)
                    } else {
                        Text(project.url).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Toggle("", isOn: Binding(get: { project.isActive }, set: onToggle))
                    .toggleStyle(.switch)
                    .tint(.hodorLight)
                    .labelsHidden()
                    .disabled(!project.hasServer || project.localPort == nil)
            }

            Picker("Server", selection: selection) {
                Text("None").tag(ServerRef?.none)
                if let selected = selection.wrappedValue, !isDiscovered(selected) {
                    Text(label(host: selected.host, port: selected.port) + " (not found)").tag(ServerRef?.some(selected))
                }
                ForEach(hosts, id: \.self) { host in
                    let servers = discovery[host]?.servers ?? []
                    if !servers.isEmpty {
                        Divider()
                    }
                    ForEach(servers) { server in
                        Text(label(host: host, port: server.port, server: server))
                            .tag(ServerRef?.some(ServerRef(host: host, port: server.port)))
                    }
                }
            }
            .labelsHidden()

            if case .failed(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.hodorWedge)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusDot: some View {
        let color: Color =
            switch status {
            case .running: .hodorLight
            case .failed: .hodorWedge
            case .inactive: .secondary.opacity(0.4)
            }
        // A running tunnel glows like the light through the open door.
        return Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: status == .running ? color : .clear, radius: 3)
    }

    /// Host and port of the selected dev server, as one picker value.
    private struct ServerRef: Hashable {
        var host: String
        var port: Int
    }

    private var selection: Binding<ServerRef?> {
        Binding(
            get: {
                guard let host = project.host, let port = project.remotePort else { return nil }
                return ServerRef(host: host, port: port)
            },
            set: {
                project.host = $0?.host
                project.remotePort = $0?.port
            }
        )
    }

    private func isDiscovered(_ ref: ServerRef) -> Bool {
        discovery[ref.host]?.servers.contains { $0.port == ref.port } ?? false
    }

    /// The host is only shown when there is more than one to choose from.
    private func label(host: String, port: Int, server: DevServer? = nil) -> String {
        var parts = hosts.count > 1 ? [host] : []
        parts.append(":\(port)")
        if let process = server?.process, !process.isEmpty { parts.append(process) }
        if let directory = server?.directory, !directory.isEmpty { parts.append(abbreviate(directory)) }
        return parts.joined(separator: "  ·  ")
    }

    /// /home/<user>/foo -> ~/foo
    private func abbreviate(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3, components[1] == "home" else { return path }
        return (["~"] + components.dropFirst(3)).joined(separator: "/")
    }
}
