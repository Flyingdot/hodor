import Foundation
import Testing

@testable import HodorCore

@MainActor
struct TunnelManagerTests {
    @Test func unresolvableHostFails() async throws {
        let manager = TunnelManager()
        let project = Project(name: "A", url: "http://localhost:14299", host: "hodor-test.invalid", remotePort: 3780, isActive: true)
        manager.sync(projects: [project])
        #expect(manager.status(for: project) == .running)

        for _ in 0..<100 where manager.status(for: project) == .running {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard case .failed(let message) = manager.status(for: project) else {
            Issue.record("expected .failed, got \(manager.status(for: project))")
            return
        }
        #expect(message.contains("hodor-test.invalid"))

        manager.sync(projects: [])
        #expect(manager.status(for: project) == .inactive)
    }

    @Test func inactiveOrIncompleteProjectsAreNotStarted() {
        let manager = TunnelManager()
        let host = "hodor-test.invalid"
        let inactive = Project(name: "A", url: "http://localhost:14299", host: host, remotePort: 3780)
        let noServer = Project(name: "B", url: "http://localhost:14298", isActive: true)
        let noHost = Project(name: "C", url: "http://localhost:14297", remotePort: 3780, isActive: true)
        let badURL = Project(name: "D", url: "nope", host: host, remotePort: 3780, isActive: true)
        let unpickedExtra = Project(
            name: "E", url: "http://localhost:14296", host: host, samePort: true,
            extraForwards: [Forward(localPort: 14295, samePort: false)], isActive: true)
        manager.sync(projects: [inactive, noServer, noHost, badURL, unpickedExtra])
        #expect(manager.statuses.isEmpty)
    }

    @Test func errorNamesTheBusyPort() {
        let busy = StderrBuffer()
        busy.append(
            Data(
                """
                bind [127.0.0.1]:10000: Address already in use
                channel_setup_fwd_listener_tcpip: cannot listen to port: 10000
                Could not request local forwarding.

                """.utf8))
        #expect(busy.message == "bind [127.0.0.1]:10000: Address already in use")

        // ssh bound the other address and kept running, so the bind line is not the reason it exited.
        let later = StderrBuffer()
        later.append(Data("bind [127.0.0.1]:4200: Address already in use\nTimeout, server winterfell not responding.\n".utf8))
        #expect(later.message == "Timeout, server winterfell not responding.")

        let chatty = StderrBuffer()
        for _ in 0..<1000 {
            chatty.append(Data("channel 2: open failed: connect failed: Connection refused\n".utf8))
        }
        chatty.append(Data("Connection to winterfell closed by remote host.\n".utf8))
        #expect(chatty.message == "Connection to winterfell closed by remote host.")

        let other = StderrBuffer()
        other.append(Data("ssh: Could not resolve hostname x: nodename nor servname provided\n".utf8))
        #expect(other.message == "ssh: Could not resolve hostname x: nodename nor servname provided")
        #expect(StderrBuffer().message == nil)
    }

    @Test func forwardsEveryPortThroughOneConnection() throws {
        let project = Project(
            name: "A", url: "https://localhost:4200", host: "winterfell", remotePort: 4201,
            extraForwards: [Forward(localPort: 10000), Forward(localPort: 10001, samePort: false, remotePort: 31544)])
        let arguments = try #require(TunnelManager.Spec(project)).arguments

        #expect(arguments.last == "winterfell")
        #expect(
            arguments.split(separator: "-L").dropFirst().map { $0.first }
                == ["4200:localhost:4201", "10000:localhost:10000", "10001:localhost:31544"])
    }
}
