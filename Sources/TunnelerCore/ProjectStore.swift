import Foundation
import Observation

struct Config: Codable {
    var host: String
    var projects: [Project]
}

/// Persists the remote host and project list as JSON in ~/Library/Application Support/Tunneler.
@MainActor
@Observable
public final class ProjectStore {
    public var host: String { didSet { save() } }
    public var projects: [Project] { didSet { save() } }

    private let fileURL: URL

    public init(fileURL: URL = ProjectStore.defaultFileURL) {
        self.fileURL = fileURL
        let config = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
        host = config?.host ?? "winterfell"
        projects = config?.projects ?? []
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tunneler/config.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Config(host: host, projects: projects)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Tunneler: failed to save config: \(error)")
        }
    }
}
