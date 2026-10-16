import HodorCore
import SwiftUI

struct ProjectRow: View {
    @Binding var project: Project
    var hosts: [String]
    var discovery: [String: HostServers]
    /// Lists every listener instead of only your processes inside git worktrees.
    var showAllServers = false
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
                // A selection that is hidden by the filter or gone from discovery stays visible at the top.
                if let selected = selection.wrappedValue, !isListed(selected) {
                    let server = discovered(selected)
                    Text(label(host: selected.host, port: selected.port, server: server) + (server == nil ? " (not found)" : ""))
                        .tag(ServerRef?.some(selected))
                }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.servers) { server in
                            Text(group.isWorktree ? worktreeLabel(server) : label(port: server.port, server: server))
                                .tag(ServerRef?.some(ServerRef(host: group.host, port: server.port)))
                        }
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

    /// Servers of one worktree on one host, or the remaining listeners of a host (`isWorktree` false).
    struct ServerGroup: Identifiable {
        var host: String
        var title: String
        var isWorktree: Bool
        var servers: [DevServer]
        var id: String { host + "\t" + title }
    }

    /// Per host: one group per worktree sorted by title, then the other listeners if `showAllServers` is on.
    var groups: [ServerGroup] {
        hosts.flatMap { host -> [ServerGroup] in
            let prefix = hosts.count > 1 ? host + "  ·  " : ""
            let servers = (discovery[host]?.servers ?? []).filter { showAllServers || $0.isDevServer }
            let byWorktree = Dictionary(grouping: servers.filter(\.isDevServer)) { $0.worktreePath }
            // Sorted by repository, then the main checkout, then the worktree folder.
            let sortKey = { (s: DevServer) in [s.repository ?? "", s.isMainCheckout ? "" : s.worktree ?? ""] }
            var result = byWorktree.values
                .sorted {
                    sortKey($0[0]).lexicographicallyPrecedes(sortKey($1[0])) { $0.localizedStandardCompare($1) == .orderedAscending }
                }
                .map { ServerGroup(host: host, title: prefix + worktreeTitle($0[0]), isWorktree: true, servers: $0) }
            let others = servers.filter { !$0.isDevServer }
            if !others.isEmpty {
                result.append(ServerGroup(host: host, title: prefix + "Other listeners", isWorktree: false, servers: others))
            }
            return result
        }
    }

    /// "repo › worktree (branch)". The worktree is left out for the main checkout, the branch when the worktree
    /// folder is already named after it (with "/" written as "+").
    private func worktreeTitle(_ server: DevServer) -> String {
        var title = server.repository ?? server.worktree ?? "?"
        if !server.isMainCheckout, let worktree = server.worktree {
            title += " › " + worktree
        }
        if let branch = server.branch, branch.replacingOccurrences(of: "/", with: "+") != server.worktree {
            title += " (\(branch))"
        }
        return title
    }

    private func discovered(_ ref: ServerRef) -> DevServer? {
        discovery[ref.host]?.servers.first { $0.port == ref.port }
    }

    private func isListed(_ ref: ServerRef) -> Bool {
        discovered(ref).map { showAllServers || $0.isDevServer } ?? false
    }

    /// ":port · subdirectory · process", for a server listed under its worktree. The process is left out when
    /// the subdirectory already ends with it, as for .NET apps built into their own executable.
    func worktreeLabel(_ server: DevServer) -> String {
        let process = server.process.flatMap { server.subdirectory?.hasSuffix("/" + $0) == true ? nil : $0 }
        return [":\(server.port)", server.subdirectory, process].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// ":port · process · directory". The host is only shown when given and there is more than one.
    private func label(host: String? = nil, port: Int, server: DevServer? = nil) -> String {
        var parts = hosts.count > 1 ? [host].compactMap { $0 } : []
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
