import AppKit
import HodorCore

/// Owns the store and the tunnels, and keeps them in sync even while the menu is closed.
@MainActor
final class AppModel {
    let store = ProjectStore()
    let tunnels = TunnelManager()
    let links = ControlLinks()
    private let server: ControlServer
    private var signalSources: [DispatchSourceSignal] = []

    init() {
        let control = AgentControl(store: store, tunnels: tunnels)
        server = ControlServer(path: AgentScript.socketPath) { args in await control.handle(args) }
        // A closed pipe or socket must fail the write, not kill the app.
        signal(SIGPIPE, SIG_IGN)
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
        ) { [tunnels, links, server] _ in
            MainActor.assumeIsolated {
                tunnels.stopAll()
                links.stopAll()
                server.stop()
            }
        }
    }

    private func sync() {
        tunnels.sync(projects: store.projects)
        syncAgentControl()
    }

    /// Opens or closes the control socket and the links to the hosts, following the setting.
    private func syncAgentControl() {
        guard store.agentControl else {
            links.stopAll()
            server.stop()
            return
        }
        if !server.isRunning {
            do {
                try AgentScript.installLocally()
                try server.start()
            } catch {
                NSLog("Hodor: agent control unavailable: \(error)")
            }
        }
        links.sync(hosts: store.hosts)
    }
}
