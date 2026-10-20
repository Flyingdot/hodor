import Foundation
import Testing

@testable import HodorCore

struct ProjectTests {
    @Test func forwardsStartWithTheURLPort() {
        let project = Project(
            name: "A", url: "https://localhost:4200", host: "winterfell", remotePort: 4201,
            extraForwards: [Forward(localPort: 10000), Forward(localPort: 10001, samePort: false, remotePort: 31544)])

        #expect(project.forwards.map(\.localPort) == [4200, 10000, 10001])
        #expect(project.forwards.map(\.target) == [4201, 10000, 31544])
        #expect(project.isComplete)
    }

    @Test func isCompleteNeedsAHostAndEveryTarget() {
        let samePort = Project(name: "A", url: "http://localhost:10000", host: "winterfell", samePort: true)
        #expect(samePort.isComplete)

        var noHost = samePort
        noHost.host = nil
        #expect(!noHost.isComplete)

        var unpicked = samePort
        unpicked.extraForwards = [Forward(localPort: 10001, samePort: false)]
        #expect(!unpicked.isComplete)

        var badURL = samePort
        badURL.url = "nope"
        #expect(!badURL.isComplete)
    }

    @Test func pickingOnAnotherHostClearsTheOtherPicks() {
        var project = Project(
            name: "A", url: "https://localhost:4200", host: "winterfell", remotePort: 4201,
            extraForwards: [Forward(localPort: 10000), Forward(localPort: 10001, samePort: false, remotePort: 31544)])

        project.pick(31000, on: "winterfell", forwardAt: 2)
        #expect(project.remotePort == 4201)
        #expect(project.extraForwards[1].remotePort == 31000)

        project.pick(8080, on: "castle-black", forwardAt: 0)
        #expect(project.host == "castle-black")
        #expect(project.remotePort == 8080)
        #expect(project.extraForwards.map(\.target) == [10000, nil])

        project.pick(nil, on: nil, forwardAt: 0)
        #expect(project.host == "castle-black")
        #expect(project.remotePort == nil)
    }

    @Test func parsesPortsAndRanges() {
        #expect(Forward.parsePorts("5000") == [5000])
        #expect(Forward.parsePorts("10000-10002") == [10000, 10001, 10002])
        #expect(Forward.parsePorts(" 5000, 10000-10001 6000 ") == [5000, 10000, 10001, 6000])
        #expect(Forward.parsePorts("") == nil)
        #expect(Forward.parsePorts("abc") == nil)
        #expect(Forward.parsePorts("0") == nil)
        #expect(Forward.parsePorts("65536") == nil)
        #expect(Forward.parsePorts("10002-10000") == nil)
        #expect(Forward.parsePorts("10000-") == nil)
        #expect(Forward.parsePorts("1-2-3") == nil)
        #expect(Forward.parsePorts("10000-20000") == nil)
    }
}
