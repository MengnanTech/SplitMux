import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let settings = SettingsManager.shared

    var body: some View {
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
        }
        .frame(width: 450, height: 320)
        .padding()
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
