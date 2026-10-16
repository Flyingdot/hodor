import Testing

@testable import HodorCore

struct DevServerDiscoveryTests {
    @Test func parsesNormalLines() {
        let output = "3780\t1384\tnode-MainThread\t/home/dani/worktrees/a\n4201\t2000\tnode\t/home/dani/b\n"
        #expect(
            DevServerDiscovery.parse(output) == [
                DevServer(port: 3780, pid: 1384, process: "node-MainThread", directory: "/home/dani/worktrees/a"),
                DevServer(port: 4201, pid: 2000, process: "node", directory: "/home/dani/b"),
            ])
    }

    @Test func missingPidLeavesFieldsNil() {
        #expect(DevServerDiscovery.parse("22\t\t\t\n631\t\t\t") == [DevServer(port: 22), DevServer(port: 631)])
    }

    @Test func toleratesShortLines() {
        #expect(DevServerDiscovery.parse("22\n4200\t17") == [DevServer(port: 22), DevServer(port: 4200, pid: 17)])
    }

    @Test func ignoresBlankAndGarbageLines() {
        let output = "\n   \nbash: ss: command not found\nabc\t1\tx\ty\n0\t\t\t\n70000\t\t\t\n8080\t\t\t\n"
        #expect(DevServerDiscovery.parse(output) == [DevServer(port: 8080)])
    }

    @Test func deduplicatesByPortPreferringPid() {
        let output = "22\t\t\t\n4200\t\t\t\n4200\t42\tnode\t/srv\n22\t\t\t\n4200\t43\tother\t/x\n"
        #expect(
            DevServerDiscovery.parse(output) == [
                DevServer(port: 22),
                DevServer(port: 4200, pid: 42, process: "node", directory: "/srv"),
            ])
    }

    @Test func sortsByPort() {
        #expect(DevServerDiscovery.parse("8080\t\t\t\n22\t\t\t\n4200\t\t\t").map(\.port) == [22, 4200, 8080])
    }

    @Test func parsesGitFields() {
        let output =
            "3000\t7\tdcp\t/home/dani/app/.claude/worktrees/feat+x/src/web\t/home/dani/app/.claude/worktrees/feat+x\t/home/dani/app/.git\tfeat/x\n"
            + "4200\t8\tnode\t/srv/repo\t/srv/repo\t/srv/repo/.git\tHEAD\n"
        let servers = DevServerDiscovery.parse(output)
        #expect(
            servers == [
                DevServer(
                    port: 3000, pid: 7, process: "dcp", directory: "/home/dani/app/.claude/worktrees/feat+x/src/web",
                    worktreePath: "/home/dani/app/.claude/worktrees/feat+x", gitCommonDir: "/home/dani/app/.git", branch: "feat/x"),
                DevServer(
                    port: 4200, pid: 8, process: "node", directory: "/srv/repo", worktreePath: "/srv/repo",
                    gitCommonDir: "/srv/repo/.git"),
            ])
        #expect(servers.map(\.repository) == ["app", "repo"])
        #expect(servers.map(\.worktree) == ["feat+x", "repo"])
        #expect(servers.map(\.isMainCheckout) == [false, true])
        #expect(servers.map(\.subdirectory) == ["src/web", nil])
    }

    @Test func bareRepositoryNameDropsGitExtension() {
        #expect(DevServer(port: 1, gitCommonDir: "/srv/app.git").repository == "app")
    }

    @Test func devServerNeedsPidAndWorktree() {
        #expect(DevServer(port: 1, pid: 2, worktreePath: "/w").isDevServer)
        #expect(!DevServer(port: 1, pid: 2, directory: "/home/dani").isDevServer)
        #expect(!DevServer(port: 22).isDevServer)
    }

    @Test func remoteCommandHasNoSingleQuotesInsideScript() {
        let command = DevServerDiscovery.remoteCommand
        #expect(command.hasPrefix("sh -c '") && command.hasSuffix("'"))
        #expect(command.dropFirst(7).dropLast().contains("'") == false)
    }
}

struct ProjectLocalPortTests {
    @Test(arguments: [
        ("https://localhost:4200", 4200),
        ("http://localhost:8080/path", 8080),
        ("https://localhost", 443),
        ("http://localhost", 80),
        ("HTTPS://localhost", 443),
    ])
    func validURLs(url: String, port: Int) {
        #expect(Project.localPort(of: url) == port)
    }

    @Test(arguments: ["", "localhost:4200", "not a url", "ftp://localhost", "https://"])
    func invalidURLs(url: String) {
        #expect(Project.localPort(of: url) == nil)
    }
}
