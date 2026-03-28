import SwiftUI

/// Editor sheet for adding/editing SSH host configurations
struct SSHHostEditorView: View {
    @Bindable var host: SSHHost
    let isNew: Bool
    var onSave: (SSHHost) -> Void
    var onCancel: () -> Void

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New SSH Host" : "Edit SSH Host")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.tertiaryText)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().overlay(theme.subtleBorder)

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

            Divider().overlay(theme.subtleBorder)

            // Footer buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.subtleOverlay)
                    )

                Button(action: { onSave(host) }) {
                    Text(isNew ? "Add Host" : "Save")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(host.hostname.isEmpty ? theme.accentColor.opacity(0.4) : theme.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(host.hostname.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 440, height: 500)
        .background(theme.elevatedSurface)
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
