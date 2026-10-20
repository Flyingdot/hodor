import HodorCore
import SwiftUI

/// Inline form to add a project (project == nil) or edit name, URL and forwarded ports of an existing one.
struct ProjectForm: View {
    var project: Project?
    var onSave: (Project) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var url = "https://localhost:4200"
    @State private var urlTouched = false
    @State private var samePort = false
    @State private var extraForwards: [Forward] = []
    @State private var newPorts = ""
    @State private var newPortsInvalid = false
    @FocusState private var focused: Field?

    private enum Field { case name, url }

    private var urlPort: Int? {
        Project.localPort(of: url)
    }

    /// Whether the URL's port is also in the additional ports.
    private var urlPortTwice: Bool {
        extraForwards.contains { $0.localPort == urlPort }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && urlPort != nil && !urlPortTwice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $name)
                .focused($focused, equals: .name)
            TextField("URL", text: $url)
                .focused($focused, equals: .url)
                .onSubmit(save)
            if urlTouched && urlPort == nil {
                error("Enter a URL with a port, e.g. https://localhost:4200")
            } else if urlTouched, let urlPort, urlPortTwice {
                error("Port \(urlPort) is also an additional port")
            }

            if let urlPort {
                portRow(urlPort, samePort: $samePort) {
                    Text("from the URL").font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("Additional ports").font(.caption).foregroundStyle(.secondary)
            ForEach($extraForwards, id: \.localPort) { $forward in
                portRow(forward.localPort, samePort: $forward.samePort) {
                    Button {
                        extraForwards.removeAll { $0.localPort == forward.localPort }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove port")
                }
            }
            HStack {
                TextField("5000 or 10000-10002", text: $newPorts)
                    .onSubmit(addPorts)
                Button("Add", systemImage: "plus", action: addPorts)
                    .disabled(newPorts.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if newPortsInvalid {
                error("Enter ports between 1 and 65535, e.g. 5000 or 10000-10002")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(project == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            if let project {
                name = project.name
                url = project.url
                samePort = project.samePort
                extraForwards = project.extraForwards
            }
            NSApp.activate(ignoringOtherApps: true)
            focused = .name
        }
        .onChange(of: focused) { old, _ in
            if old == .url { urlTouched = true }
        }
        .onChange(of: newPorts) { newPortsInvalid = false }
    }

    /// "10000  [Same port ⌄]  <trailing>"
    private func portRow(_ port: Int, samePort: Binding<Bool>, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(String(port))
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)
            Picker("Target", selection: samePort) {
                Text("Pick server").tag(false)
                Text("Same port").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            trailing()
            Spacer()
        }
    }

    private func error(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.hodorWedge)
    }

    /// Adds the typed ports as same-port forwards, skipping ports that are already forwarded.
    private func addPorts() {
        guard let ports = Forward.parsePorts(newPorts) else {
            newPortsInvalid = true
            return
        }
        var updated = extraForwards
        for port in ports where port != urlPort && !updated.contains(where: { $0.localPort == port }) {
            updated.append(Forward(localPort: port))
        }
        extraForwards = updated
        newPorts = ""
    }

    private func save() {
        guard isValid else { return }
        var result = project ?? Project(name: "", url: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.url = url.trimmingCharacters(in: .whitespaces)
        result.samePort = samePort
        if samePort { result.remotePort = nil }
        result.extraForwards = extraForwards.map { $0.samePort ? Forward(localPort: $0.localPort) : $0 }
        onSave(result)
    }
}
