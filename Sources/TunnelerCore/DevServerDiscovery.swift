import Foundation

/// Lists TCP listeners on the remote host via `ssh <host> ss -tlnp`.
public enum DevServerDiscovery {
    // STUB: implemented in work package 2.
    public static func discover(host: String) async throws -> [DevServer] {
        []
    }

    public static func parse(_ output: String) -> [DevServer] {
        []
    }
}
