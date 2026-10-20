import Foundation

/// Lists TCP listeners on the remote host via `ssh <host> ss -tlnp`.
public enum DevServerDiscovery {
    public struct Failure: LocalizedError {
        public var message: String
        public var errorDescription: String? { message }
    }

    /// POSIX sh snippet printing
    /// `port<TAB>pid<TAB>process<TAB>cwd<TAB>worktree<TAB>gitCommonDir<TAB>branch<TAB>argv0<TAB>script`
    /// per listener reachable via `localhost` on the remote host. The process is the executable's name, since
    /// `/proc/<pid>/comm` is cut at 15 characters. The git fields stay empty outside a repo.
    /// `argv0` and `script` (the first argument not starting with `-`) are only sent for node, to name it.
    /// Wrapped in `sh -c` because the remote login shell may not be POSIX (e.g. fish).
    /// Contains no single quotes, so it can be single-quoted as a whole.
    static let remoteCommand: String = {
        let script = [
            "ss -Htlnp | while read -r state recvq sendq local peer rest; do",
            "addr=${local%:*}; port=${local##*:};",
            "case $addr in 127.0.0.1|0.0.0.0|\"*\"|\"[::]\"|\"[::1]\") ;; *) continue ;; esac;",
            "pid=$(echo \"$rest\" | sed -n \"s/.*pid=\\([0-9]*\\).*/\\1/p\");",
            "comm=; cwd=; top=; common=; branch=; argv0=; script=;",
            "if [ -n \"$pid\" ]; then exe=$(readlink /proc/$pid/exe 2>/dev/null); comm=${exe##*/};",
            "[ -n \"$comm\" ] || comm=$(cat /proc/$pid/comm 2>/dev/null); cwd=$(readlink /proc/$pid/cwd 2>/dev/null); fi;",
            "if [ \"$comm\" = node ]; then args=$(tr \"\\0\\t\" \"\\n \" < /proc/$pid/cmdline 2>/dev/null);",
            "argv0=$(echo \"$args\" | head -n 1); script=$(echo \"$args\" | tail -n +2 | grep -v \"^-\" | head -n 1); fi;",
            "if [ -n \"$cwd\" ]; then",
            "g=$(git -C \"$cwd\" rev-parse --path-format=absolute --show-toplevel --git-common-dir --abbrev-ref HEAD 2>/dev/null);",
            "top=$(echo \"$g\" | sed -n 1p); common=$(echo \"$g\" | sed -n 2p); branch=$(echo \"$g\" | sed -n 3p); fi;",
            "printf \"%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n\" \"$port\" \"$pid\" \"$comm\" \"$cwd\" \"$top\" \"$common\" \"$branch\"",
            "\"$argv0\" \"$script\";",
            "done",
        ].joined(separator: " ")
        return "sh -c '\(script)'"
    }()

    public static func discover(host: String) async throws -> [DevServer] {
        let args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, remoteCommand]
        let (status, stdout, stderr) = try await Task.detached { try run("/usr/bin/ssh", args) }.value
        guard status == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: "ssh \(host) failed (exit \(status))" + (detail.isEmpty ? "" : ": \(detail)"))
        }
        return parse(stdout)
    }

    /// Parses the tab-separated output of `remoteCommand`. Deduplicates by port (preferring entries with a pid)
    /// and sorts by port. Lines without a valid port are ignored.
    public static func parse(_ output: String) -> [DevServer] {
        var byPort: [Int: DevServer] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let port = Int(fields[0].trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else { continue }
            func field(_ i: Int) -> String? {
                guard i < fields.count else { return nil }
                let value = fields[i].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            let server = DevServer(
                port: port, pid: field(1).flatMap { Int($0) },
                process: field(2).map { processName(executable: $0, argv0: field(7), script: field(8)) }, directory: field(3),
                worktreePath: field(4), gitCommonDir: field(5), branch: field(6).flatMap { $0 == "HEAD" ? nil : $0 })
            if let existing = byPort[port], existing.pid != nil || server.pid == nil { continue }
            byPort[port] = server
        }
        return byPort.values.sorted { $0.port < $1.port }
    }

    /// Names a node process after what it runs: a process title it set (`next-server (v16.4.0)` → `next-server`),
    /// else its script (`…/vite/bin/vite.js` → `vite`). Other executables keep their name.
    static func processName(executable: String, argv0: String?, script: String?) -> String {
        guard executable == "node" else { return executable }
        if let title = argv0?.split(separator: " ").first.map(String.init),
            !title.contains("/"), title != "node"
        {
            return title
        }
        if let script, let name = script.split(separator: "/").last {
            let base = (String(name) as NSString).deletingPathExtension
            if !base.isEmpty { return base }
        }
        return executable
    }

    /// Runs a process to completion and returns exit status, stdout and stderr. Blocks; call off the main thread.
    private static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read stderr concurrently so neither pipe can fill up and block the child.
        nonisolated(unsafe) var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) { errData = err.fileHandleForReading.readDataToEndOfFile() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }
}
