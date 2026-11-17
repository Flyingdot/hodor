import Foundation
import Testing

@testable import HodorCore

@MainActor
struct AgentControlTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hodor-tests-\(UUID().uuidString)/config.json")

    nonisolated static let worktree = "/home/dani/dev/app/.claude/worktrees/feature+login"
    nonisolated static let servers = [
        DevServer(port: 22),
        DevServer(
            port: 4317, pid: 101, process: "node", directory: worktree + "/web", worktreePath: worktree,
            gitCommonDir: "/home/dani/dev/app/.git", branch: "feature/login"),
        DevServer(
            port: 4201, pid: 102, process: "dotnet", directory: "/home/dani/dev/app/api", worktreePath: "/home/dani/dev/app",
            gitCommonDir: "/home/dani/dev/app/.git", branch: "main"),
        DevServer(
            port: 5001, pid: 103, process: "dotnet", directory: "/home/dani/dev/app/api", worktreePath: "/home/dani/dev/app",
            gitCommonDir: "/home/dani/dev/app/.git", branch: "main"),
    ]

    private func control(_ projects: [Project]) -> (ProjectStore, AgentControl) {
        let store = ProjectStore(fileURL: fileURL)
        store.projects = projects
        let control = AgentControl(
            store: store, tunnels: TunnelManager(), discover: { _ in Self.servers }, probe: { _ in false },
            pollInterval: .milliseconds(50))
        return (store, control)
    }

    @Test func usePointsTheActivePresetAtTheWorktreesServer() async {
        let off = Project(name: "App main", url: "https://localhost:4300", host: "winterfell", remotePort: 4201)
        let on = Project(name: "App other", url: "https://localhost:4300", host: "winterfell", remotePort: 4999, isActive: true)
        let (store, control) = control([off, on])

        let reply = await control.handle(["use", "4300", "--worktree", Self.worktree + "/web/src"])

        #expect(reply.ok, "\(reply.text)")
        #expect(reply.text.contains("winterfell:4317"))
        #expect(store.projects[1].remotePort == 4317)
        #expect(store.projects[1].isActive)
        #expect(store.projects[1].agentChangedAt != nil)
        #expect(store.projects[0] == off)
    }

    @Test func useByNameActivatesAndTurnsOffTheOtherPreset() async {
        let a = Project(name: "App main", url: "https://localhost:4300", host: "winterfell", remotePort: 4201, isActive: true)
        let b = Project(name: "App other", url: "https://localhost:4300", host: "winterfell")
        let (store, control) = control([a, b])

        let reply = await control.handle(["use", "app other", "--port", "4317"])

        #expect(reply.ok, "\(reply.text)")
        #expect(store.projects.map(\.isActive) == [false, true])
        #expect(store.projects[1].remotePort == 4317)
    }

    @Test func ambiguousPresetsAreRejected() async {
        let (store, control) = control([
            Project(name: "A", url: "https://localhost:4300", host: "winterfell"),
            Project(name: "B", url: "https://localhost:4300", host: "winterfell"),
        ])
        let reply = await control.handle(["use", "4300", "--port", "4317"])
        #expect(!reply.ok)
        #expect(reply.text.contains("Several projects"))
        #expect(store.projects.allSatisfy { $0.remotePort == nil })
    }

    @Test func pinnedProjectsStayAsTheyAre() async {
        let pinned = Project(name: "A", url: "https://localhost:4300", host: "winterfell", remotePort: 4201, isPinned: true)
        let (store, control) = control([pinned])
        for args in [["use", "4300", "--port", "4317"], ["off", "4300"], ["on", "A"]] {
            let reply = await control.handle(args)
            #expect(!reply.ok)
            #expect(reply.text.contains("pinned"))
        }
        #expect(store.projects == [pinned])
    }

    @Test func worktreeWithSeveralServersNeedsAPort() async {
        let (store, control) = control([Project(name: "A", url: "https://localhost:4300")])

        let ambiguous = await control.handle(["use", "4300", "--worktree", "/home/dani/dev/app"])
        #expect(!ambiguous.ok)
        #expect(ambiguous.text.contains(":4201") && ambiguous.text.contains(":5001") && ambiguous.text.contains("--port"))

        let picked = await control.handle(["use", "4300", "--worktree", "/home/dani/dev/app/", "--port", "5001"])
        #expect(picked.ok, "\(picked.text)")
        #expect(store.projects[0].host == "winterfell")
        #expect(store.projects[0].remotePort == 5001)
    }

    @Test func worktreeWithoutServerListsTheOthers() async {
        let (_, control) = control([Project(name: "A", url: "https://localhost:4300")])
        let reply = await control.handle(["use", "4300", "--worktree", "/home/dani/dev/other"])
        #expect(!reply.ok)
        #expect(reply.text.contains("winterfell:" + Self.worktree))
        // A sibling folder that merely starts with the worktree's name isn't inside it.
        let sibling = await control.handle(["use", "4300", "--worktree", "/home/dani/dev/application"])
        #expect(!sibling.ok)
    }

    @Test func samePortProjectHasNothingToPick() async {
        let (_, control) = control([Project(name: "Storage", url: "http://localhost:10000", host: "winterfell", samePort: true)])
        let reply = await control.handle(["use", "10000", "--port", "10000"])
        #expect(!reply.ok)
        #expect(reply.text.contains("same port"))
    }

    @Test func incompleteProjectIsSavedButStaysOff() async {
        let project = Project(
            name: "A", url: "https://localhost:4300", host: "winterfell",
            extraForwards: [Forward(localPort: 5000, samePort: false)])
        let (store, control) = control([project])
        let reply = await control.handle(["use", "4300", "--port", "4317"])
        #expect(!reply.ok)
        #expect(reply.text.contains(":5000"))
        #expect(store.projects[0].remotePort == 4317)
        #expect(!store.projects[0].isActive)
    }

    @Test func onAndOff() async {
        let (store, control) = control([Project(name: "A", url: "https://localhost:4300", host: "winterfell", remotePort: 4317)])
        #expect(await control.handle(["on", "4300"]).ok)
        #expect(store.projects[0].isActive)
        #expect(await control.handle(["off", "a"]).ok)
        #expect(!store.projects[0].isActive)
    }

    @Test func listsProjectsAndServers() async {
        let (_, control) = control([
            Project(name: "App", url: "https://localhost:4300", host: "winterfell", remotePort: 4317, isPinned: true)
        ])
        let projects = await control.handle(["projects"])
        #expect(projects.ok)
        #expect(projects.text == "4300  App  https://localhost:4300  winterfell:4317  off, pinned")

        let servers = await control.handle(["servers"])
        #expect(servers.ok)
        #expect(servers.text.contains(":4317  node"))
        #expect(!servers.text.contains(":22 "))
        #expect(await control.handle(["servers", "--all"]).text.contains(":22 "))
    }

    @Test func statusWaitFailsForAProjectThatIsOff() async {
        let (_, control) = control([Project(name: "A", url: "https://localhost:4300", host: "winterfell", remotePort: 4317)])
        let reply = await control.handle(["status", "4300", "--wait", "1"])
        #expect(!reply.ok)
        #expect(reply.text.contains("is off"))
    }

    @Test func rejectsUnknownInput() async {
        let (_, control) = control([Project(name: "A", url: "https://localhost:4300", host: "winterfell")])
        #expect(await control.handle(["frobnicate"]).text.contains("Unknown command"))
        #expect(await control.handle(["use", "4300", "--force"]).text.contains("Unknown option"))
        #expect(await control.handle(["use", "4300", "--port", "99999"]).text.contains("isn't a port"))
        #expect(await control.handle(["use", "4300", "--port", "1", "--host", "nope"]).text.contains("Unknown host"))
        #expect(await control.handle(["use", "4300"]).text.contains("--worktree"))
        #expect(await control.handle(["help"]).ok)
    }
}

/// Runs the real `hodor` script against the real socket server.
struct ControlServerTests {
    @Test func scriptTalksToTheServer() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hodor-\(UUID().uuidString.prefix(8))")
        let socket = dir.appendingPathComponent("hodor.sock").path
        let server = ControlServer(path: socket) { args in
            AgentControl.Reply(ok: args.first != "fail", text: "args: " + args.joined(separator: "|"))
        }
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        let script = dir.appendingPathComponent("hodor")
        try Data(AgentScript.source.utf8).write(to: script)

        let ok = try run(script, socket: socket, ["use", "4300", "--worktree", "/home/dani/dir with spaces"])
        #expect(ok.status == 0)
        #expect(ok.stdout == "args: use|4300|--worktree|/home/dani/dir with spaces\n")

        let failed = try run(script, socket: socket, ["fail", "x"])
        #expect(failed.status == 1)
        #expect(failed.stdout.isEmpty)
        #expect(failed.stderr == "args: fail|x\n")

        let help = try run(script, socket: socket, [])
        #expect(help.stdout == "args: help\n")

        server.stop()
        let gone = try run(script, socket: socket, ["projects"])
        #expect(gone.status == 2)
        #expect(gone.stderr.contains("can't reach Hodor"))
    }

    @Test func installCommandIsSingleQuotedOnce() {
        let inner = ControlLinks.installCommand.dropFirst("sh -c '".count).dropLast()
        #expect(ControlLinks.installCommand.hasPrefix("sh -c '") && ControlLinks.installCommand.hasSuffix("'"))
        #expect(!inner.contains("'"))
    }

    @Test func forwardArguments() {
        let args = ControlLinks.forwardArguments(host: "winterfell", remoteSocket: "/home/d/.hodor/hodor.sock", localSocket: "/l.sock")
        #expect(args.suffix(3) == ["-R", "/home/d/.hodor/hodor.sock:/l.sock", "winterfell"])
        #expect(args.contains("ExitOnForwardFailure=yes"))
        #expect(args.contains("ControlMaster=no") && args.contains("ControlPath=none"))
    }

    private func run(_ script: URL, socket: String, _ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging(["HODOR_SOCKET": socket]) { $1 }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }
}
