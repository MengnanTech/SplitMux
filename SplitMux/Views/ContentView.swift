import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showCommandPalette = false
    @State private var showSearch = false
    @State private var searchText = ""

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 220)

                Divider()
                    .overlay(Color(white: 0.15))

                // Keep all sessions alive, show only the selected one
                ZStack {
                    ForEach(appState.sessions) { session in
                        TabContentView(session: session)
                            .opacity(session.id == appState.selectedSessionID ? 1 : 0)
                            .allowsHitTesting(session.id == appState.selectedSessionID)
                    }

                    if appState.sessions.isEmpty {
                        theme.contentBackground
                        Text("No Session")
                            .foregroundStyle(.secondary)
                            .font(.system(.title3, design: .monospaced))
                    }
                }
            }
            .background(theme.contentBackground)

            // Command Palette overlay
            if showCommandPalette {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showCommandPalette = false
                    }

                VStack {
                    CommandPaletteView(isPresented: $showCommandPalette)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Clear current tab's notification when app becomes active
            if let session = appState.selectedSession, let tab = session.activeTab {
                tab.hasNotification = false
                tab.lastNotificationMessage = nil
                appState.updateDockBadge()
            }
        }
        // MARK: - Keyboard Shortcuts
        .background {
            // Cmd+P — Command Palette
            Button("") { showCommandPalette.toggle() }
                .keyboardShortcut("p", modifiers: .command)
                .hidden()

            // Cmd+T — New Tab
            Button("") { addTab() }
                .keyboardShortcut("t", modifiers: .command)
                .hidden()

            // Cmd+N — New Session
            Button("") { appState.addSession() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()

            // Cmd+W — Close Tab
            Button("") { closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()

            // Cmd+F — Search Terminal
            Button("") {
                showSearch.toggle()
                // Forward to active TabContentView via notification
                NotificationCenter.default.post(name: .toggleTerminalSearch, object: nil)
            }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()

            // Cmd+Plus — Increase Font
            Button("") { SettingsManager.shared.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()

            // Cmd+Minus — Decrease Font
            Button("") { SettingsManager.shared.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()

            // Cmd+0 — Reset Font Size
            Button("") { SettingsManager.shared.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()

            // Cmd+D — Split Right
            Button("") { appState.selectedSession?.splitActiveTab(direction: .right) }
                .keyboardShortcut("d", modifiers: .command)
                .hidden()

            // Cmd+Shift+D — Split Down
            Button("") { appState.selectedSession?.splitActiveTab(direction: .down) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .hidden()

            // Cmd+1..9 — Switch Tabs
            ForEach(1...9, id: \.self) { i in
                Button("") { switchToTab(index: i - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
                    .hidden()
            }

            // Cmd+Shift+[ — Previous Session
            Button("") { switchSession(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .hidden()

            // Cmd+Shift+] — Next Session
            Button("") { switchSession(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .hidden()

            // Cmd+Shift+W — Close Session
            Button("") {
                if let id = appState.selectedSessionID {
                    withAnimation { appState.removeSession(id) }
                }
            }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .hidden()
        }
    }

    // MARK: - Actions

    private func addTab() {
        guard let session = appState.selectedSession else { return }
        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        withAnimation(.easeInOut(duration: 0.15)) {
            session.addTab(tab)
        }
    }

    private func closeActiveTab() {
        guard let session = appState.selectedSession,
              let tabID = session.activeTabID else { return }
        if session.tabs.count <= 1 {
            // Last tab — close session
            withAnimation { appState.removeSession(session.id) }
        } else {
            withAnimation { session.removeTab(tabID) }
        }
    }

    private func switchToTab(index: Int) {
        guard let session = appState.selectedSession,
              index < session.tabs.count else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            session.activeTabID = session.tabs[index].id
        }
    }

    private func switchSession(offset: Int) {
        guard let currentID = appState.selectedSessionID,
              let currentIndex = appState.sessions.firstIndex(where: { $0.id == currentID }) else { return }
        let newIndex = (currentIndex + offset + appState.sessions.count) % appState.sessions.count
        withAnimation(.easeOut(duration: 0.12)) {
            appState.selectedSessionID = appState.sessions[newIndex].id
        }
    }
}

extension Notification.Name {
    static let toggleTerminalSearch = Notification.Name("toggleTerminalSearch")
}
