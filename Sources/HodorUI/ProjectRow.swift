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
                    .disabled(!project.isComplete)
            }

            let forwards = project.forwards
            let picked = forwards.indices.filter { !forwards[$0].samePort }
            ForEach(picked, id: \.self) { index in
                if forwards.count == 1 {
                    serverPicker(forwardAt: index)
                } else {
                    HStack {
                        Text(String(forwards[index].localPort) + " →")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        serverPicker(forwardAt: index)
                    }
                }
            }

            // Same-port forwards still need a host. With a single host it's set when the project is saved.
            if picked.isEmpty && (hosts.count > 1 || project.host.map(hosts.contains) != true) {
                Picker("Host", selection: $project.host) {
                    Text("None").tag(String?.none)
                    ForEach(hosts, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
            }

            // The closed picker only shows the item, so name its worktree below.
            if let worktree = selectedWorktree {
                Text(worktree)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            let samePorts = forwards.filter(\.samePort).map(\.localPort)
            if !samePorts.isEmpty {
                samePortLine(samePorts)
            }

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

    /// Picked server of the forward at `index` in `project.forwards`.
    private func selection(at index: Int) -> Binding<ServerRef?> {
        Binding(
            get: {
                let forwards = project.forwards
                guard forwards.indices.contains(index), !forwards[index].samePort, let host = project.host,
                    let port = forwards[index].remotePort
                else { return nil }
                return ServerRef(host: host, port: port)
            },
            set: { project.pick($0?.port, on: $0?.host, forwardAt: index) }
        )
    }

    private func serverPicker(forwardAt index: Int) -> some View {
        let selection = selection(at: index)
        return Picker("Server", selection: selection) {
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
    }

    /// "⇄ 10000  10001  10002 · same port". Ports nothing listens on remotely are dimmed and named below.
    private func samePortLine(_ ports: [Int]) -> some View {
        let missing = notListening(ports)
        let list = ports.enumerated().reduce(Text("")) { text, item in
            let port = Text(String(item.element))
                .foregroundStyle(missing.contains(item.element) ? HierarchicalShapeStyle.tertiary : .primary)
            return item.offset == 0 ? port : text + Text("  ") + port
        }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "arrow.left.arrow.right")
                list.monospacedDigit()
                Spacer()
                Text("same port").foregroundStyle(.secondary)
            }
            if !missing.isEmpty {
                Text("nothing listening on " + missing.map { ":\($0)" }.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    /// Ports of `ports` without a listener on the project's host. Empty until discovery has a result.
    func notListening(_ ports: [Int]) -> [Int] {
        guard let host = project.host, let result = discovery[host], result.error == nil,
            !(result.isLoading && result.servers.isEmpty)
        else { return [] }
        let listening = Set(result.servers.map(\.port))
        return ports.filter { !listening.contains($0) }
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

    /// Section titles of the selected servers, e.g. "app › feature+login", each once. Nil when none is in a worktree.
    var selectedWorktree: String? {
        var titles: [String] = []
        for index in project.forwards.indices {
            guard let ref = selection(at: index).wrappedValue, let server = discovered(ref), server.isDevServer else { continue }
            let title = worktreeTitle(server)
            if !titles.contains(title) { titles.append(title) }
        }
        guard let host = project.host, !titles.isEmpty else { return nil }
        return (hosts.count > 1 ? host + "  ·  " : "") + titles.joined(separator: ", ")
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
