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
        store.host = "example"
        store.projects = [Project(name: "A", url: "https://localhost:4200", remotePort: 4201)]

        let reloaded = ProjectStore(fileURL: fileURL)

        #expect(reloaded.host == "example")
        #expect(reloaded.projects == store.projects)
    }

    @Test func defaultsToWinterfell() {
        #expect(ProjectStore(fileURL: fileURL).host == "winterfell")
    }
}
