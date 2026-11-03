import ServiceManagement
import SwiftUI

/// Checkbox that adds Hodor to the Login Items, so it starts with the Mac and restores the active tunnels.
/// The state lives in the system, not in the config. It's read again on every open, since the user can also
/// change it in System Settings.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Open at login", isOn: Binding(get: { status == .enabled }, set: setEnabled))
                .toggleStyle(.checkbox)
                .help("Start Hodor when you log in. Active tunnels come back with it.")
            if status == .requiresApproval {
                Button("Allow in System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.hodorWedge)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
