import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var theme: AppTheme { SettingsManager.shared.theme }

    private var results: [PaletteItem] {
        let items = buildItems()
        if query.isEmpty { return items }
        let q = query.lowercased()
        let filtered = items.filter { item in
            let text = (item.title + " " + item.subtitle).lowercased()
            return text.contains(q)
        }
        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.sectionHeaderText)

                TextField("Search sessions, tabs, commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.primaryText)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelected()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.tabBarBackground)

            Divider().overlay(theme.subtleBorder)

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            PaletteItemRow(item: item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    if newValue < results.count {
                        proxy.scrollTo(results[newValue].id, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(theme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !results.isEmpty else { return .handled }
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private func buildItems() -> [PaletteItem] {
        var items: [PaletteItem] = []

        // Sessions and tabs
        for session in appState.sessions {
            items.append(PaletteItem(
                id: "session-\(session.id)",
                icon: session.icon,
                title: session.name,
                subtitle: session.displayPath,
                kind: .session,
                shortcut: nil,
                action: {
                    appState.selectedSessionID = session.id
                }
            ))

            for tab in session.tabs {
                items.append(PaletteItem(
                    id: "tab-\(tab.id)",
                    icon: tab.icon,
                    title: tab.title,
                    subtitle: "in \(session.name)",
                    kind: .tab,
                    shortcut: nil,
                    action: {
                        appState.selectedSessionID = session.id
                        session.activeTabID = tab.id
                    }
                ))
            }
        }

        // Commands with keyboard shortcuts
        items.append(PaletteItem(
            id: "cmd-new-session",
            icon: "plus.rectangle",
            title: "New Session",
            subtitle: "Create a new terminal session",
            kind: .command,
            shortcut: "\u{2318}N",
            action: { appState.addSession() }
        ))
        items.append(PaletteItem(
            id: "cmd-new-tab",
            icon: "plus.square",
            title: "New Tab",
            subtitle: "Add a tab to current session",
            kind: .command,
            shortcut: "\u{2318}T",
            action: {
                if let session = appState.selectedSession {
                    let tab = session.createTab()
                    session.addTab(tab)
                }
            }
        ))
        items.append(PaletteItem(
            id: "cmd-split-right",
            icon: "rectangle.split.2x1",
            title: "Split Right",
            subtitle: "Split active pane horizontally",
            kind: .command,
            shortcut: "\u{2318}D",
            action: {
                appState.selectedSession?.splitActiveTab(direction: .right)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-split-down",
            icon: "rectangle.split.1x2",
            title: "Split Down",
            subtitle: "Split active pane vertically",
            kind: .command,
            shortcut: "\u{21E7}\u{2318}D",
            action: {
                appState.selectedSession?.splitActiveTab(direction: .down)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-search",
            icon: "magnifyingglass",
            title: "Search Terminal",
            subtitle: "Find text in terminal output",
            kind: .command,
            shortcut: "\u{2318}F",
            action: {
                NotificationCenter.default.post(name: .toggleTerminalSearch, object: nil)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-settings",
            icon: "gear",
            title: "Open Settings",
            subtitle: "Configure SplitMux preferences",
            kind: .command,
            shortcut: nil,
            action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-history",
            icon: "clock.arrow.circlepath",
            title: "Toggle Terminal History",
            subtitle: "Show/hide terminal output history panel",
            kind: .command,
            shortcut: "\u{21E7}\u{2318}H",
            action: {
                NotificationCenter.default.post(name: .toggleTerminalHistory, object: nil)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-agents",
            icon: "cpu",
            title: "Agent Dashboard",
            subtitle: "View and manage Claude Code agents",
            kind: .command,
            shortcut: "\u{21E7}\u{2318}A",
            action: {
                NotificationCenter.default.post(name: .showAgentDashboard, object: nil)
            }
        ))

        // SSH Hosts
        for host in SSHManagerService.shared.allHosts {
            items.append(PaletteItem(
                id: "ssh-\(host.id)",
                icon: "network",
                title: "SSH: \(host.displayName)",
                subtitle: "\(host.username.isEmpty ? "" : "\(host.username)@")\(host.hostname)\(host.port != 22 ? ":\(host.port)" : "")",
                kind: .sshHost,
                shortcut: nil,
                action: { [weak appState] in
                    guard let session = appState?.selectedSession else { return }
                    let tab = Tab(
                        title: host.displayName,
                        icon: "network",
                        content: .sshTerminal(hostID: host.id)
                    )
                    tab.sshHostID = host.id
                    session.addTab(tab)
                }
            ))
        }

        return items
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        results[selectedIndex].action()
        isPresented = false
    }
}

struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let kind: PaletteItemKind
    let shortcut: String?
    let action: () -> Void

    enum PaletteItemKind {
        case session, tab, command, sshHost
    }
}

struct PaletteItemRow: View {
    let item: PaletteItem
    let isSelected: Bool

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(kindColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.bodyText)

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer()

            // Keyboard shortcut hint
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.hoverBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(kindLabel)
                .font(.system(size: 10))
                .foregroundStyle(theme.disabledText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.hoverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? theme.hoverBackground : .clear)
        .contentShape(Rectangle())
    }

    private var kindColor: Color {
        switch item.kind {
        case .session: return .green
        case .tab: return .blue
        case .command: return .orange
        case .sshHost: return .cyan
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .session: return "Session"
        case .tab: return "Tab"
        case .command: return "Command"
        case .sshHost: return "SSH"
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
