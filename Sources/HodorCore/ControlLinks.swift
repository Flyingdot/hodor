import Foundation
import Observation

/// Lets agents on the hosts reach the control socket. Per host, installs `~/.hodor/hodor` there, then keeps an
/// `ssh -N -R <host's ~/.hodor/hodor.sock>:<socket on this Mac>` running and retries it every 5 s when it drops.
@MainActor
@Observable
public final class ControlLinks {
    /// `.running` while the ssh process is up, `.failed` with ssh's error while it waits for a retry.
    public private(set) var statuses: [String: TunnelStatus] = [:]
    @ObservationIgnored private var links: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let localSocket: String

    public init(localSocket: String = AgentScript.socketPath) {
        self.localSocket = localSocket
    }

    public func status(for host: String) -> TunnelStatus {
        statuses[host] ?? .inactive
    }

    /// Starts links to new hosts and stops those to hosts no longer listed.
    public func sync(hosts: [String]) {
        for (host, task) in links where !hosts.contains(host) {
            task.cancel()
            links[host] = nil
            statuses[host] = nil
        }
        for host in hosts where links[host] == nil {
            links[host] = Task { await self.run(host) }
        }
    }

    public func stopAll() {
        sync(hosts: [])
    }

    private func run(_ host: String) async {
        while !Task.isCancelled {
            do {
                let home = try await install(on: host)
                try Task.checkCancellation()
                statuses[host] = .running
                try await forward(host, remoteSocket: home + "/.hodor/hodor.sock")
            } catch {
                guard !Task.isCancelled else { return }
                statuses[host] = .failed((error as? DevServerDiscovery.Failure)?.message ?? error.localizedDescription)
            }
            try? await Task.sleep(for: TunnelManager.retryDelay)
        }
    }

    /// Remote side of `install`: writes the script from stdin, removes a socket left by an earlier connection (sshd
    /// won't replace it) and prints the home directory, since `-R` needs an absolute path.
    /// Wrapped in `sh -c` because the login shell may be fish.
    nonisolated static let installCommand =
        "sh -c 'umask 077 && mkdir -p ~/.hodor && chmod 700 ~/.hodor && cat > ~/.hodor/hodor.new"
        + " && chmod 755 ~/.hodor/hodor.new && mv ~/.hodor/hodor.new ~/.hodor/hodor && rm -f ~/.hodor/hodor.sock"
        + " && echo \"$HOME\"'"

    /// Installs the script on the host and returns the host's home directory.
    private func install(on host: String) async throws -> String {
        let args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, Self.installCommand]
        let input = Data(AgentScript.source.utf8)
        let (status, stdout, stderr) = try await Task.detached {
            try DevServerDiscovery.run("/usr/bin/ssh", args, input: input)
        }.value
        let home = stdout.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        guard status == 0, home.hasPrefix("/") else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DevServerDiscovery.Failure(
                message: "installing hodor on \(host) failed (exit \(status))" + (detail.isEmpty ? "" : ": \(detail)"))
        }
        return home
    }

    /// Connection sharing is off, like for the tunnels: a master would take the forward over and ssh would exit 0.
    nonisolated static func forwardArguments(host: String, remoteSocket: String, localSocket: String) -> [String] {
        [
            "-N", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
            "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            "-R", "\(remoteSocket):\(localSocket)", host,
        ]
    }

    /// Runs the ssh process until it exits, which always throws. Cancelling the task terminates it.
    private func forward(_ host: String, remoteSocket: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.forwardArguments(host: host, remoteSocket: remoteSocket, localSocket: localSocket)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        let buffer = StderrBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        let box = ProcessBox(process)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    let message = buffer.message ?? "ssh exited with code \(process.terminationStatus)"
                    continuation.resume(throwing: DevServerDiscovery.Failure(message: message))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                // Cancelled before the process started: the handler below had nothing to stop yet.
                if Task.isCancelled { process.terminate() }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

/// Lets the cancellation handler, which runs on any thread, stop the process.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
