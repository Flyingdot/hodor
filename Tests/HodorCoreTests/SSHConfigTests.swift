import Testing

@testable import HodorCore

struct SSHConfigTests {
    @Test func readsHostLines() {
        let text = """
            Host *
              ServerAliveInterval 30

            Host winterfell castle-black
              HostName 10.0.0.2
            host=dragonstone
            \tHost\tthe-wall
            HostName winterfell.example
            """
        #expect(SSHConfig.hostAliases(in: text) == ["winterfell", "castle-black", "dragonstone", "the-wall"])
    }

    @Test func skipsPatternsAndDuplicates() {
        let text = "Host web-? !bastion prod-* winterfell\nHost winterfell\n"
        #expect(SSHConfig.hostAliases(in: text) == ["winterfell"])
    }
}
