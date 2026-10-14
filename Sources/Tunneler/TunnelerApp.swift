import SwiftUI
import TunnelerCore

@main
struct TunnelerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: model.store, tunnels: model.tunnels)
        } label: {
            let anyRunning = model.store.projects.contains { model.tunnels.status(for: $0) == .running }
            Image(systemName: anyRunning ? "point.3.filled.connected.trianglepath.dotted" : "point.3.connected.trianglepath.dotted")
        }
        .menuBarExtraStyle(.window)
    }
}
