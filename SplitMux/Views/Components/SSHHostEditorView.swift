import SwiftUI

/// Editor sheet for adding/editing SSH host configurations
struct SSHHostEditorView: View {
    @Bindable var host: SSHHost
    let isNew: Bool
    var onSave: (SSHHost) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New SSH Host" : "Edit SSH Host")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider().overlay(Color(white: 0.2))

            // Form
            Form {
                Section("Connection") {
                    TextField("Display Name", text: $host.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Hostname", text: $host.hostname)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("22", value: $host.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    TextField("Username", text: $host.username)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Authentication") {
                    HStack {
                        TextField("Identity File", text: Binding(
                            get: { host.keyPath ?? "" },
                            set: { host.keyPath = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            pickKeyFile()
                        }
                    }
                }

                Section("Options") {
                    Picker("Color Tag", selection: $host.colorTag) {
                        ForEach(SSHColorTag.allCases) { tag in
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 10, height: 10)
                                Text(tag.rawValue.capitalized)
                            }
                            .tag(tag)
                        }
                    }

                    Toggle("Auto-reconnect on disconnect", isOn: $host.autoReconnect)
                }
            }
            .formStyle(.grouped)

            Divider().overlay(Color(white: 0.2))

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(isNew ? "Add Host" : "Save") {
                    onSave(host)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.hostname.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select SSH identity file"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            host.keyPath = url.path
        }
    }
}
