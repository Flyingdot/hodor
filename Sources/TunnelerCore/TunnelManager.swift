import Foundation
import Observation

/// Runs one `ssh -N -L` process per active project.
@MainActor
@Observable
public final class TunnelManager {
    public private(set) var statuses: [UUID: TunnelStatus] = [:]

    public init() {}

    public func status(for project: Project) -> TunnelStatus {
        statuses[project.id] ?? .inactive
    }

    // STUB: implemented in work package 2.
    /// Starts, restarts or stops tunnels so that exactly the active projects with a selected server are forwarded.
    public func sync(projects: [Project], host: String) {}

    public func stopAll() {}
}
