import Foundation
import Observation

struct Config: Codable {
    var host: String
    var projects: [Project]
}

/// Persists the remote host and project list as JSON in ~/Library/Application Support/Hodor.
@MainActor
@Observable
public final class ProjectStore {
    public var host: String { didSet { save() } }
    public var projects: [Project] { didSet { save() } }
    /// Called after every change, once it is saved.
    @ObservationIgnored public var onChange: (() -> Void)?

    private let fileURL: URL

    public init(fileURL: URL = ProjectStore.defaultFileURL) {
        self.fileURL = fileURL
        let config = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
        host = config?.host ?? "winterfell"
        projects = config?.projects ?? []
    }

    /// Activates or deactivates a project. Activating turns off other projects on the same local port,
    /// since only one tunnel can bind it.
    public func setActive(_ active: Bool, for id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var updated = projects
        if active, let port = updated[index].localPort {
            for i in updated.indices where i != index && updated[i].localPort == port {
                updated[i].isActive = false
            }
        }
        updated[index].isActive = active
        projects = updated
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hodor/config.json")
    }

    private func save() {
        defer { onChange?() }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Config(host: host, projects: projects)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Hodor:failed to save config: \(error)")
        }
    }
}
