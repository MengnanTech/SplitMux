import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.trailing, 10)
            }

            TabView {
                GeneralSettingsTab(settings: settings)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                TerminalSettingsTab(settings: settings)
                    .tabItem {
                        Label("Terminal", systemImage: "terminal")
                    }

                ThemeSettingsTab(settings: settings)
                    .tabItem {
                        Label("Theme", systemImage: "paintpalette")
                    }

                NotificationSettingsTab(settings: settings)
                    .tabItem {
                        Label("Notifications", systemImage: "bell")
                    }

                SSHSettingsTab()
                    .tabItem {
                        Label("SSH", systemImage: "network")
                    }

                HistorySettingsTab()
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
            }
        }
        .frame(width: 500, height: 460)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Form {
            Toggle("Restore sessions on launch", isOn: Binding(
                get: { settings.restoreSessionsOnLaunch },
                set: { settings.restoreSessionsOnLaunch = $0 }
            ))

            Toggle("Confirm before closing session", isOn: Binding(
                get: { settings.confirmBeforeClose },
                set: { settings.confirmBeforeClose = $0 }
            ))
        }
        .formStyle(.grouped)
    }
}

struct TerminalSettingsTab: View {
    @Bindable var settings: SettingsManager

    private let fontOptions = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier New",
        "Andale Mono"
    ]

    var body: some View {
        Form {
            Picker("Font", selection: Binding(
                get: { settings.fontName },
                set: { settings.fontName = $0 }
            )) {
                ForEach(fontOptions, id: \.self) { name in
                    Text(name).font(.custom(name, size: 13))
                }
            }

            HStack {
                Text("Font Size: \(Int(settings.fontSize))pt")
                Spacer()
                Stepper("", value: Binding(
                    get: { settings.fontSize },
                    set: { settings.fontSize = $0 }
                ), in: 9...32, step: 1)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemeSettingsTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Form {
            Picker("Theme", selection: Binding(
                get: { settings.theme },
                set: { settings.theme = $0 }
            )) {
                ForEach(AppTheme.allCases) { theme in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.contentBackground)
                            .frame(width: 20, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        Text(theme.displayName)
                    }
                    .tag(theme)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
    }
}

struct NotificationSettingsTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Form {
            Toggle("Show notification banners", isOn: Binding(
                get: { settings.showNotificationBanners },
                set: { settings.showNotificationBanners = $0 }
            ))

            HStack {
                Text("Notification delay: \(Int(settings.notifyThresholdSeconds))s")
                Spacer()
                Stepper("", value: Binding(
                    get: { settings.notifyThresholdSeconds },
                    set: { settings.notifyThresholdSeconds = $0 }
                ), in: 1...60, step: 1)
                .labelsHidden()
            }

            Text("Commands finishing faster than this threshold won't trigger notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct SSHSettingsTab: View {
    private let sshManager = SSHManagerService.shared

    var body: some View {
        Form {
            Section("Saved Hosts") {
                if sshManager.savedHosts.isEmpty {
                    Text("No saved SSH hosts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sshManager.savedHosts) { host in
                        HStack {
                            Circle()
                                .fill(host.colorTag.color)
                                .frame(width: 8, height: 8)
                            Text(host.displayName)
                            Spacer()
                            Text("\(host.username)@\(host.hostname)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("SSH Config") {
                HStack {
                    Text("~/.ssh/config hosts: \(sshManager.configHosts.count)")
                    Spacer()
                    Button("Refresh") {
                        sshManager.refreshConfig()
                    }
                }
                Text("SplitMux automatically reads hosts from your SSH config file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct HistorySettingsTab: View {
    private let historyService = TerminalHistoryService.shared

    var body: some View {
        Form {
            Toggle("Record terminal output", isOn: Binding(
                get: { historyService.isRecordingEnabled },
                set: { historyService.isRecordingEnabled = $0 }
            ))

            HStack {
                Text("Max memory per tab:")
                Spacer()
                Picker("", selection: Binding(
                    get: { historyService.maxBytesPerTab },
                    set: { historyService.maxBytesPerTab = $0 }
                )) {
                    Text("10 MB").tag(10_000_000)
                    Text("25 MB").tag(25_000_000)
                    Text("50 MB").tag(50_000_000)
                    Text("100 MB").tag(100_000_000)
                }
                .frame(width: 120)
            }

            Section("Usage") {
                HStack {
                    Text("Active histories:")
                    Spacer()
                    Text("\(historyService.activeHistories.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total memory:")
                    Spacer()
                    Text(historyService.totalSizeString)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Terminal output is recorded in memory for search, export, and replay. History is not persisted across app restarts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
