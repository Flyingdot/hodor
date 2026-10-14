import HodorCore
import SwiftUI

/// Inline form to add a project (project == nil) or edit name and URL of an existing one.
struct ProjectForm: View {
    var project: Project?
    var onSave: (Project) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var url = "https://localhost:4200"
    @State private var urlTouched = false
    @FocusState private var focused: Field?

    private enum Field { case name, url }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Project.localPort(of: url) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $name)
                .focused($focused, equals: .name)
            TextField("URL", text: $url)
                .focused($focused, equals: .url)
                .onSubmit(save)
            if urlTouched && Project.localPort(of: url) == nil {
                Text("Enter a URL with a port, e.g. https://localhost:4200")
                    .font(.caption)
                    .foregroundStyle(Color.hodorWedge)
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
            }
            NSApp.activate(ignoringOtherApps: true)
            focused = .name
        }
        .onChange(of: focused) { old, _ in
            if old == .url { urlTouched = true }
        }
    }

    private func save() {
        guard isValid else { return }
        var result = project ?? Project(name: "", url: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.url = url.trimmingCharacters(in: .whitespaces)
        onSave(result)
    }
}
