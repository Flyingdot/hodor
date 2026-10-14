import SwiftUI
import HodorCore

struct ProjectRow: View {
    @Binding var project: Project
    var servers: [DevServer]
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
                    .labelsHidden()
                    .disabled(project.remotePort == nil || project.localPort == nil)
            }

            Picker("Server", selection: $project.remotePort) {
                Text("None").tag(Int?.none)
                if let port = project.remotePort, !servers.contains(where: { $0.port == port }) {
                    Text(":\(port) (not found)").tag(Int?.some(port))
                }
                ForEach(servers) { server in
                    Text(label(for: server)).tag(Int?.some(server.port))
                }
            }
            .labelsHidden()

            if case .failed(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusDot: some View {
        let color: Color = switch status {
        case .running: .green
        case .failed: .red
        case .inactive: .secondary.opacity(0.4)
        }
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func label(for server: DevServer) -> String {
        var parts = [":\(server.port)"]
        if let process = server.process, !process.isEmpty { parts.append(process) }
        if let directory = server.directory, !directory.isEmpty { parts.append(abbreviate(directory)) }
        return parts.joined(separator: "  ·  ")
    }

    /// /home/<user>/foo -> ~/foo
    private func abbreviate(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3, components[1] == "home" else { return path }
        return (["~"] + components.dropFirst(3)).joined(separator: "/")
    }
}
