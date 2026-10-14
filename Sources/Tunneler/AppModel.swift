import AppKit
import TunnelerCore

/// Owns the store and the tunnels, and keeps them in sync even while the menu is closed.
@MainActor
final class AppModel {
    let store = ProjectStore()
    let tunnels = TunnelManager()
    private var signalSources: [DispatchSourceSignal] = []

    init() {
        // Quit cleanly on kill/Ctrl-C too, otherwise the ssh children outlive the app and keep the ports busy.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
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
