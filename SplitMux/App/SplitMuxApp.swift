import SwiftUI
import Sparkle

@main
struct SplitMuxApp: App {
    @State private var appState = AppState()
    @State private var showSettings = false
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(SettingsManager.shared.theme.colorScheme)
                .onAppear {
                    NotificationService.shared.requestPermission()
                    appState.restoreIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showSettings = true
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.saveNow()
                }
        }
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    appState.addSession()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    if let session = appState.selectedSession {
                        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
                        session.addTab(tab)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()
            }

            // View menu — split pane
            CommandGroup(after: .toolbar) {
                Button("Split Right") {
                    appState.selectedSession?.splitActiveTab(direction: .right)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Down") {
                    appState.selectedSession?.splitActiveTab(direction: .down)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                if appState.selectedSession?.splitRoot != nil {
                    Button("Unsplit") {
                        withAnimation { appState.selectedSession?.unsplit() }
                    }
                }

                Divider()

                Button("Increase Font Size") {
                    SettingsManager.shared.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    SettingsManager.shared.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    SettingsManager.shared.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
            }

            // Edit menu — find
            CommandGroup(after: .textEditing) {
                Button("Find in Terminal") {
                    NotificationCenter.default.post(name: .toggleTerminalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // Window menu — command palette
            CommandGroup(after: .windowArrangement) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // App menu — Check for Updates
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Sparkle Check for Updates

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
    }
}

extension Notification.Name {
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
}
