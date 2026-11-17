import Foundation

/// Answers the commands agents send with `hodor`. Agents can point existing projects at a server and turn them on
/// or off. They can't add or delete projects or hosts, or touch pinned projects.
@MainActor
public final class AgentControl {
    public struct Reply: Equatable, Sendable {
        public var ok: Bool
        public var text: String

        public init(ok: Bool, text: String) {
            self.ok = ok
            self.text = text
        }
    }

    struct Failure: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    private let store: ProjectStore
    private let tunnels: TunnelManager
    private let discover: @Sendable (String) async throws -> [DevServer]
    private let probe: @Sendable (URL) async -> Bool
    /// Time between checks while `--wait` waits.
    private let pollInterval: Duration

    public convenience init(store: ProjectStore, tunnels: TunnelManager) {
        self.init(store: store, tunnels: tunnels, discover: DevServerDiscovery.discover(host:), probe: HTTPProbe.answers)
    }

    /// Tests pass a stub instead of ssh and the HTTP check.
    init(
        store: ProjectStore, tunnels: TunnelManager, discover: @escaping @Sendable (String) async throws -> [DevServer],
        probe: @escaping @Sendable (URL) async -> Bool, pollInterval: Duration = .seconds(1)
    ) {
        self.store = store
        self.tunnels = tunnels
        self.discover = discover
        self.probe = probe
        self.pollInterval = pollInterval
    }

    static let usage = """
        hodor: steer Hodor, the menu bar app that forwards fixed URLs on the user's Mac (e.g. https://localhost:4300)
        to dev servers over ssh. Point a project at your dev server so the user, or an agent on the Mac, can open it
        at its usual URL.

          hodor projects                     List projects: local URL, current target, status.
          hodor servers [--host H] [--all]   List dev servers (your processes in git worktrees) on the hosts.
          hodor use P --worktree DIR [--port N] [--wait]
                                             Point project P at the dev server running in DIR's git worktree and turn
                                             it on. Add --port N, the port your server listens on: worktrees
                                             usually have other listeners too, such as the agent itself.
          hodor use P --port N [--host H] [--wait]
                                             Point project P at port N on its host and turn it on.
          hodor on P / hodor off P           Turn project P on or off.
          hodor status P [--wait [SECONDS]]  Show whether P is running and its URL answers. --wait blocks until it
                                             answers (default 60 s) and fails on timeout.

        P is the project's local port (4300) or its name. Turning a project on turns off other projects on the same
        local port. Projects the user pinned can't be changed. Projects and hosts are set up by the user in Hodor.
        Example: hodor use 4300 --worktree "$PWD" --port 4311 --wait
        """

    public func handle(_ args: [String]) async -> Reply {
        guard let command = args.first else { return Reply(ok: true, text: Self.usage) }
        do {
            let options = try Options(Array(args.dropFirst()))
            switch command {
            case "help", "--help", "-h": return Reply(ok: true, text: Self.usage)
            case "projects", "list": return Reply(ok: true, text: projectList())
            case "servers": return Reply(ok: true, text: try await servers(options))
            case "use": return try await use(options)
            case "on", "off": return Reply(ok: true, text: try toggle(options, on: command == "on"))
            case "status": return try await status(options)
            default: throw Failure("Unknown command \"\(command)\". Run `hodor help`.")
            }
        } catch let failure as Failure {
            return Reply(ok: false, text: failure.message)
        } catch {
            return Reply(ok: false, text: error.localizedDescription)
        }
    }

    // MARK: - Commands

    private func projectList() -> String {
        guard !store.projects.isEmpty else { return "No projects. The user adds them in Hodor." }
        return table(store.projects.map { [String($0.localPort ?? 0), $0.name, $0.url, target(of: $0), state(of: $0)] })
    }

    private func servers(_ options: Options) async throws -> String {
        let hosts = try hostsToSearch(options)
        var lines: [[String]] = []
        for (host, result) in await discoverAll(hosts) {
            switch result {
            case .success(let servers):
                for server in servers where options.flag("all") || server.isDevServer {
                    let branch = server.branch.map { "(\($0))" } ?? ""
                    lines.append([host, ":\(server.port)", server.process ?? "?", server.directory ?? "", branch])
                }
            case .failure(let error):
                lines.append([host, "error: " + error.localizedDescription])
            }
        }
        return lines.isEmpty ? "No dev servers found." : table(lines)
    }

    private func use(_ options: Options) async throws -> Reply {
        var project = try changeable(options)
        guard let first = project.forwards.first, project.localPort != nil else {
            throw Failure("\(project.name) has no port in its URL (\(project.url)).")
        }
        guard !first.samePort else {
            throw Failure("\(project.name) forwards :\(first.localPort) to the same port on its host. There's nothing to pick.")
        }
        let port = try options.value("port").map(Self.port)

        let host: String
        let remotePort: Int
        if let directory = options.value("worktree") {
            (host, remotePort) = try await server(in: directory, port: port, options: options)
        } else if let port {
            guard let found = options.value("host") ?? project.host ?? (store.hosts.count == 1 ? store.hosts.first : nil) else {
                throw Failure("\(project.name) has no host yet. Add --host (one of: \(store.hosts.joined(separator: ", "))).")
            }
            guard store.hosts.contains(found) else { throw unknownHost(found) }
            (host, remotePort) = (found, port)
        } else {
            throw Failure("Say which server: --worktree DIR or --port N.")
        }

        project.pick(remotePort, on: host, forwardAt: 0)
        project.agentChangedAt = Date()
        store.projects = store.projects.map { $0.id == project.id ? project : $0 }
        var text = "\(project.name) (\(project.url)) → \(host):\(remotePort)"
        guard project.isComplete else {
            let missing = project.forwards.filter { $0.target == nil }.map { ":\($0.localPort)" }
            return Reply(ok: false, text: text + ", but it stays off: no server for \(missing.joined(separator: ", ")). Ask the user.")
        }
        store.setActive(true, for: project.id)
        guard options.flag("wait") else {
            return Reply(ok: true, text: text + ", on. Check it with: hodor status \(project.localPort ?? 0) --wait")
        }
        let reply = try await waitUntilAnswers(project.id, timeout: options.timeout)
        text += "\n" + reply.text
        return Reply(ok: reply.ok, text: text)
    }

    private func toggle(_ options: Options, on: Bool) throws -> String {
        let project = try changeable(options)
        if on && !project.isComplete {
            throw Failure("\(project.name) can't be turned on: it has no host or a forward has no server. Use `hodor use`.")
        }
        store.setActive(on, for: project.id)
        return "\(project.name) is \(on ? "on" : "off")."
    }

    private func status(_ options: Options) async throws -> Reply {
        let project = try self.project(options)
        if options.flag("wait") {
            return try await waitUntilAnswers(project.id, timeout: options.timeout)
        }
        var text = "\(project.name) (\(project.url)) → \(target(of: project)): \(state(of: project))"
        if tunnels.status(for: project) == .running, let url = URL(string: project.url) {
            text += await probe(url) ? ", answers" : ", no answer"
        }
        return Reply(ok: true, text: text)
    }

    /// Waits until the tunnel runs and the URL answers. ssh retries a failed tunnel by itself, so a failure only
    /// counts once the time is up.
    private func waitUntilAnswers(_ id: UUID, timeout: Duration) async throws -> Reply {
        let deadline = ContinuousClock.now + timeout
        while true {
            guard let project = store.projects.first(where: { $0.id == id }) else { throw Failure("The project was deleted.") }
            guard project.isActive else { throw Failure("\(project.name) is off.") }
            let status = tunnels.status(for: project)
            if status == .running, let url = URL(string: project.url), await probe(url) {
                return Reply(ok: true, text: "\(project.url) answers.")
            }
            if ContinuousClock.now >= deadline {
                var text = "\(project.url) doesn't answer after \(timeout.components.seconds) s"
                if case .failed(let message) = status {
                    text += ". ssh: " + message
                } else if status == .running {
                    text += ". The tunnel runs, so nothing answers on \(target(of: project))"
                }
                return Reply(ok: false, text: text + ".")
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    // MARK: - Lookup

    /// The project named by the first argument: its URL's local port or its name. Several projects can share a port
    /// (presets for the same URL). Then the one that is on wins.
    private func project(_ options: Options) throws -> Project {
        guard let ref = options.positional.first else { throw Failure("Name a project: its local port or name.") }
        let matches =
            Int(ref).map { port in store.projects.filter { $0.localPort == port } }
            ?? store.projects.filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        if matches.count == 1 { return matches[0] }
        guard !matches.isEmpty else {
            throw Failure("No project \"\(ref)\". Projects:\n" + projectList())
        }
        let active = matches.filter(\.isActive)
        if active.count == 1 { return active[0] }
        throw Failure(
            "Several projects match \"\(ref)\": \(matches.map(\.name).joined(separator: ", ")), none of them on. Ask the user which one.")
    }

    private func changeable(_ options: Options) throws -> Project {
        let project = try project(options)
        guard !project.isPinned else {
            throw Failure("\(project.name) is pinned by the user. Ask them to unpin it in Hodor.")
        }
        return project
    }

    /// The dev server in the git worktree containing `directory`. `port` picks one when there are several.
    private func server(in directory: String, port: Int?, options: Options) async throws -> (String, Int) {
        let directory = directory.hasSuffix("/") && directory.count > 1 ? String(directory.dropLast()) : directory
        var candidates: [(host: String, server: DevServer)] = []
        var worktrees: Set<String> = []
        var errors: [String] = []
        for (host, result) in await discoverAll(try hostsToSearch(options)) {
            switch result {
            case .success(let servers):
                for server in servers where server.isDevServer {
                    guard let worktree = server.worktreePath else { continue }
                    worktrees.insert("\(host):\(worktree)")
                    if directory == worktree || directory.hasPrefix(worktree + "/") {
                        candidates.append((host, server))
                    }
                }
            case .failure(let error):
                errors.append("\(host): \(error.localizedDescription)")
            }
        }
        // Worktrees can be nested (e.g. app/.claude/worktrees/x inside the main checkout app): the innermost one counts.
        let innermost = candidates.compactMap(\.server.worktreePath).max { $0.count < $1.count }
        candidates = candidates.filter { $0.server.worktreePath == innermost }
        let errorNote = errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n")
        guard !candidates.isEmpty else {
            let known = worktrees.isEmpty ? "none" : worktrees.sorted().joined(separator: "\n  ")
            throw Failure(
                "No dev server is running in the worktree of \(directory). Start it first. Worktrees with servers:\n  \(known)"
                    + errorNote)
        }
        if let port {
            guard let match = candidates.first(where: { $0.server.port == port }) else {
                throw Failure("Nothing in that worktree listens on :\(port). It has: \(describe(candidates)).")
            }
            return (match.host, port)
        }
        guard candidates.count == 1 else {
            throw Failure("The worktree has several servers: \(describe(candidates)). Add --port.")
        }
        return (candidates[0].host, candidates[0].server.port)
    }

    private func describe(_ candidates: [(host: String, server: DevServer)]) -> String {
        candidates.map { ":\($0.server.port) \($0.server.process ?? "?") (\($0.server.subdirectory ?? "."))" }
            .joined(separator: ", ")
    }

    private func hostsToSearch(_ options: Options) throws -> [String] {
        guard let host = options.value("host") else { return store.hosts }
        guard store.hosts.contains(host) else { throw unknownHost(host) }
        return [host]
    }

    private func unknownHost(_ host: String) -> Failure {
        Failure("Unknown host \"\(host)\". Hosts: \(store.hosts.joined(separator: ", ")). The user adds hosts in Hodor.")
    }

    /// Discovers all hosts in parallel, in the order given.
    private func discoverAll(_ hosts: [String]) async -> [(String, Result<[DevServer], Error>)] {
        let discover = self.discover
        // Plain tasks: a task group that collected the results came back empty in release builds.
        let tasks = hosts.map { host in Task { try await discover(host) } }
        var results: [(String, Result<[DevServer], Error>)] = []
        for (host, task) in zip(hosts, tasks) {
            results.append((host, await task.result))
        }
        return results
    }

    // MARK: - Formatting

    private func target(of project: Project) -> String {
        guard let first = project.forwards.first else { return "no port" }
        let host = project.host ?? "no host"
        var text = first.samePort ? "\(host) (same port)" : first.remotePort.map { "\(host):\($0)" } ?? "no server"
        if project.forwards.count > 1 { text += " +\(project.forwards.count - 1) ports" }
        return text
    }

    private func state(of project: Project) -> String {
        var text: String
        switch tunnels.status(for: project) {
        case .running: text = "running"
        case .failed(let message): text = "failed: " + message.replacingOccurrences(of: "\n", with: " ")
        case .inactive: text = project.isActive ? "on, incomplete" : "off"
        }
        if project.isPinned { text += ", pinned" }
        return text
    }

    /// Left-aligned columns separated by two spaces.
    private func table(_ rows: [[String]]) -> String {
        let columns = rows.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { index, cell in
                index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    static func port(_ text: String) throws -> Int {
        guard let port = Int(text), (1...65535).contains(port) else { throw Failure("\"\(text)\" isn't a port.") }
        return port
    }

    /// Positional arguments plus `--name value` options and `--flag`s.
    struct Options {
        var positional: [String] = []
        var values: [String: String] = [:]
        var flags: Set<String> = []

        static let valued: Set<String> = ["worktree", "port", "host"]

        init(_ args: [String]) throws {
            var index = 0
            while index < args.count {
                let arg = args[index]
                index += 1
                guard arg.hasPrefix("--") else {
                    positional.append(arg)
                    continue
                }
                let name = String(arg.dropFirst(2))
                if Self.valued.contains(name) {
                    guard index < args.count else { throw Failure("--\(name) needs a value.") }
                    values[name] = args[index]
                    index += 1
                } else if name == "wait" {
                    flags.insert(name)
                    // An optional number of seconds.
                    if index < args.count, let seconds = Int(args[index]) {
                        values["timeout"] = String(seconds)
                        index += 1
                    }
                } else if name == "all" {
                    flags.insert(name)
                } else {
                    throw Failure("Unknown option --\(name). Run `hodor help`.")
                }
            }
        }

        func value(_ name: String) -> String? { values[name] }
        func flag(_ name: String) -> Bool { flags.contains(name) }

        var timeout: Duration {
            .seconds(values["timeout"].flatMap(Int.init) ?? 60)
        }
    }
}

/// Checks whether a local URL answers HTTP at all, whatever the status. Accepts self-signed certificates, since
/// dev servers often use one.
public enum HTTPProbe {
    public static func answers(_ url: URL) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config, delegate: TrustingDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(from: url)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    private final class TrustingDelegate: NSObject, URLSessionDelegate, Sendable {
        func urlSession(
            _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let trust = challenge.protectionSpace.serverTrust
            else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(trust: trust))
        }
    }
}
