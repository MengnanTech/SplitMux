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
                .background(WindowConfigurator())
                .toolbar(removing: .title)
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
                    ClaudeHookService.shared.cleanup()
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

            // Window menu — command palette + agent dashboard + history
            CommandGroup(after: .windowArrangement) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Agent Dashboard") {
                    NotificationCenter.default.post(name: .showAgentDashboard, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Terminal History") {
                    NotificationCenter.default.post(name: .toggleTerminalHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
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

// MARK: - Window Configurator

/// Persistently configures the NSWindow for seamless title bar.
/// Observes window changes to reapply settings when SwiftUI resets them.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfiguratorView {
        WindowConfiguratorView()
    }

    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) {}
}

class WindowConfiguratorView: NSView {
    private var kvoObservation: NSKeyValueObservation?
    private var toolbarObservation: NSKeyValueObservation?
    private var notificationToken: NSObjectProtocol?
    private var isApplying = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        kvoObservation = nil
        toolbarObservation = nil
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
            self.notificationToken = nil
        }
        guard let window else {
            return
        }
        applyConfig(window)

        // KVO: whenever SwiftUI resets styleMask, immediately re-insert fullSizeContentView
        kvoObservation = window.observe(\.styleMask, options: [.new]) { [weak self] win, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isApplying else { return }
                self.applyConfig(win)
            }
        }
        toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] win, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isApplying else { return }
                self.applyConfig(win)
            }
        }
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyConfig(window)
            }
        }
    }

    private func applyConfig(_ window: NSWindow) {
        isApplying = true
        WindowChromeConfigurator.apply(to: window)
        isApplying = false
    }
}
