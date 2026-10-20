import Foundation
import Observation

/// Runs one `ssh -N` process per active project, with one `-L` per forward.
@MainActor
@Observable
public final class TunnelManager {
    public private(set) var statuses: [UUID: TunnelStatus] = [:]

    struct Spec: Equatable {
        var host: String
        /// Local and remote port of each forward.
        var ports: [Ports]

        struct Ports: Equatable {
            var local: Int
            var remote: Int
        }

        var arguments: [String] {
            [
                "-N", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            ] + ports.flatMap { ["-L", "\($0.local):localhost:\($0.remote)"] } + [host]
        }

        init?(_ project: Project) {
            guard project.isComplete, let host = project.host else { return nil }
            self.host = host
            ports = project.forwards.compactMap { forward in forward.target.map { Ports(local: forward.localPort, remote: $0) } }
        }
    }

    /// One entry per desired tunnel. `process` is nil while waiting for a retry.
    private struct Tunnel {
        var spec: Spec
        var process: Process?
        var retry: Task<Void, Never>?
    }

    @ObservationIgnored private var tunnels: [UUID: Tunnel] = [:]

    static let retryDelay: Duration = .seconds(5)

    public init() {}

    public func status(for project: Project) -> TunnelStatus {
        statuses[project.id] ?? .inactive
    }

    /// Starts, restarts or stops tunnels so that exactly the active and complete projects are forwarded.
    public func sync(projects: [Project]) {
        var desired: [UUID: Spec] = [:]
        for project in projects where project.isActive {
            desired[project.id] = Spec(project)
        }
        for (id, tunnel) in tunnels where desired[id] != tunnel.spec {
            stop(id)
        }
        for (id, spec) in desired where tunnels[id] == nil {
            start(id, spec)
        }
    }

    public func stopAll() {
        for id in Array(tunnels.keys) {
            stop(id)
        }
    }

    private func start(_ id: UUID, _ spec: Spec) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = spec.arguments
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
        let processID = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor in
                self?.processExited(id, processID, message: buffer.message ?? "ssh exited with code \(code)")
            }
        }

        tunnels[id] = Tunnel(spec: spec, process: process)
        do {
            try process.run()
            statuses[id] = .running
        } catch {
            fail(id, message: error.localizedDescription)
        }
    }

    private func stop(_ id: UUID) {
        guard let tunnel = tunnels.removeValue(forKey: id) else { return }
        tunnel.retry?.cancel()
        // Removing the entry first makes `processExited` ignore this termination.
        tunnel.process?.terminate()
        statuses[id] = nil
    }

    private func processExited(_ id: UUID, _ processID: ObjectIdentifier, message: String) {
        // Ignore processes that were stopped or replaced in the meantime.
        guard let process = tunnels[id]?.process, ObjectIdentifier(process) == processID else { return }
        fail(id, message: message)
    }

    /// Marks the tunnel as failed and retries after a delay as long as it is still desired.
    private func fail(_ id: UUID, message: String) {
        statuses[id] = .failed(message)
        tunnels[id]?.process = nil
        tunnels[id]?.retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled, let self, let tunnel = self.tunnels[id], tunnel.process == nil else { return }
            self.start(id, tunnel.spec)
        }
    }
}

/// Collects stderr output from a background thread.
final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        lock.withLock { text += String(decoding: data, as: UTF8.self) }
    }

    /// The `bind …` lines that name a busy port, since ssh ends those with a generic "Could not request local
    /// forwarding.". Otherwise the last line.
    var message: String? {
        let lines = lock.withLock {
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let bind = lines.filter { $0.hasPrefix("bind ") }
        return bind.isEmpty ? lines.last : bind.joined(separator: "\n")
    }
}
