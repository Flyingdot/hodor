import HodorCore
import HodorUI
import SwiftUI

@main
struct HodorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: model.store, tunnels: model.tunnels)
        } label: {
            let anyRunning = model.store.projects.contains { model.tunnels.status(for: $0) == .running }
            // Hodor holds the door open while at least one tunnel is up.
            Image(nsImage: MenuBarIcon.image(open: anyRunning))
        }
        .menuBarExtraStyle(.window)
    }
}
