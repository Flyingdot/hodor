import Foundation
import Testing

@testable import HodorCore

@MainActor
struct ProjectStoreTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hodor-tests-\(UUID().uuidString)/config.json")

    @Test func activatingDeactivatesOtherProjectsOnSamePort() {
        let store = ProjectStore(fileURL: fileURL)
        let a = Project(name: "A", url: "https://localhost:4200", remotePort: 4201, isActive: true)
        let b = Project(name: "B", url: "https://localhost:4200", remotePort: 4202)
        let c = Project(name: "C", url: "http://localhost:8080", remotePort: 8081, isActive: true)
        store.projects = [a, b, c]

        store.setActive(true, for: b.id)

        #expect(store.projects.map(\.isActive) == [false, true, true])
    }

    @Test func persistsAndReloads() {
        let store = ProjectStore(fileURL: fileURL)
        store.addHost("example")
        store.projects = [Project(name: "A", url: "https://localhost:4200", host: "example", remotePort: 4201)]

        let reloaded = ProjectStore(fileURL: fileURL)

        #expect(reloaded.hosts == ["winterfell", "example"])
        #expect(reloaded.projects == store.projects)
    }

    @Test func persistsShowAllServers() {
        let store = ProjectStore(fileURL: fileURL)
        #expect(!store.showAllServers)
        store.showAllServers = true
        #expect(ProjectStore(fileURL: fileURL).showAllServers)
    }

    @Test func defaultsToWinterfell() {
        #expect(ProjectStore(fileURL: fileURL).hosts == ["winterfell"])
    }

    @Test func migratesSingleHostConfig() throws {
        let legacy = """
            {
              "host" : "castle-black",
              "projects" : [
                { "id" : "711EC1AE-2CAE-4D8C-A207-DFBD19F09196", "isActive" : true, "name" : "A",
                  "remotePort" : 4200, "url" : "https://localhost:4200" },
                { "id" : "22222222-2222-2222-2222-222222222222", "isActive" : false, "name" : "B",
                  "url" : "https://localhost:4300" }
              ]
            }
            """
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: fileURL)

        let store = ProjectStore(fileURL: fileURL)

        #expect(store.hosts == ["castle-black"])
        #expect(store.projects.map(\.host) == ["castle-black", nil])
        #expect(store.projects[0].isActive)
    }

    @Test func addHostIgnoresBlanksAndDuplicates() {
        let store = ProjectStore(fileURL: fileURL)
        store.addHost(" castle-black ")
        store.addHost("castle-black")
        store.addHost("winterfell")
        store.addHost("  ")

        #expect(store.hosts == ["winterfell", "castle-black"])
    }

    @Test func removeHostDeselectsItsProjects() {
        let store = ProjectStore(fileURL: fileURL)
        store.addHost("castle-black")
        store.projects = [
            Project(name: "A", url: "https://localhost:4200", host: "castle-black", remotePort: 4201, isActive: true),
            Project(name: "B", url: "https://localhost:4300", host: "winterfell", remotePort: 4301, isActive: true),
        ]

        store.removeHost("castle-black")

        #expect(store.hosts == ["winterfell"])
        #expect(store.projects[0].hasServer == false)
        #expect(store.projects[0].isActive == false)
        #expect(store.projects[1].isActive)
    }
}
