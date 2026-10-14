import AppKit
import TunnelerCore

/// Owns the store and the tunnels, and keeps them in sync even while the menu is closed.
@MainActor
final class AppModel {
    let store = ProjectStore()
    let tunnels = TunnelManager()

    init() {
        store.onChange = { [unowned self] in sync() }
        sync()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [tunnels] _ in
            MainActor.assumeIsolated { tunnels.stopAll() }
        }
    }

    private func sync() {
        tunnels.sync(projects: store.projects, host: store.host)
    }
}
