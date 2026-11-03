import ServiceManagement
import SwiftUI

/// Whether Hodor is in the Login Items, so it starts with the Mac and restores the active tunnels.
/// The state lives in the system, not in the config. `refresh()` reads it again, since the user can also
/// change it in System Settings.
@MainActor @Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    private(set) var error: String?
    /// Nil in tests, which pass a fixed state instead.
    private let service: SMAppService?

    init() {
        service = .mainApp
        status = .notRegistered
    }

    init(status: SMAppService.Status, error: String? = nil) {
        service = nil
        self.status = status
        self.error = error
    }

    /// Registered, though macOS may still wait for approval.
    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        guard let service else { return }
        status = service.status
        error = nil
    }

    func setOn(_ on: Bool) {
        guard let service else { return }
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = service.status
    }
}

struct LoginItemToggle: View {
    var item: LoginItem

    var body: some View {
        Toggle("Open at login", isOn: Binding(get: { item.isOn }, set: item.setOn))
            .toggleStyle(.checkbox)
            .help("Start Hodor when you log in. Active tunnels come back with it.")
    }
}

/// The approval link or the last error, shown below the footer.
struct LoginItemNotice: View {
    var item: LoginItem

    var body: some View {
        if item.status == .requiresApproval {
            Button("Allow Hodor in System Settings › Login Items") { SMAppService.openSystemSettingsLoginItems() }
                .buttonStyle(.link)
                .font(.caption)
        }
        if let error = item.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(Color.hodorWedge)
        }
    }
}
