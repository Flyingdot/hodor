import Foundation
import Testing
@testable import TunnelerCore

@MainActor
struct TunnelManagerTests {
    @Test func unresolvableHostFails() async throws {
        let manager = TunnelManager()
        let project = Project(name: "A", url: "http://localhost:14299", remotePort: 3780, isActive: true)
        manager.sync(projects: [project], host: "tunneler-test.invalid")
        #expect(manager.status(for: project) == .running)

        for _ in 0..<100 where manager.status(for: project) == .running {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard case .failed(let message) = manager.status(for: project) else {
            Issue.record("expected .failed, got \(manager.status(for: project))")
            return
        }
        #expect(message.contains("tunneler-test.invalid"))

        manager.sync(projects: [], host: "tunneler-test.invalid")
        #expect(manager.status(for: project) == .inactive)
    }

    @Test func inactiveOrIncompleteProjectsAreNotStarted() {
        let manager = TunnelManager()
        let inactive = Project(name: "A", url: "http://localhost:14299", remotePort: 3780)
        let noServer = Project(name: "B", url: "http://localhost:14298", isActive: true)
        let badURL = Project(name: "C", url: "nope", remotePort: 3780, isActive: true)
        manager.sync(projects: [inactive, noServer, badURL], host: "tunneler-test.invalid")
        #expect(manager.statuses.isEmpty)
    }
}
