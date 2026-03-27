import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0

    private var results: [PaletteItem] {
        let items = buildItems()
        if query.isEmpty { return items }
        let q = query.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(white: 0.5))

                TextField("Search sessions, tabs, commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .onSubmit {
                        executeSelected()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))

            Divider().overlay(Color(white: 0.2))

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            PaletteItemRow(item: item, isSelected: index == selectedIndex)
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
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
                    action: {
                        appState.selectedSessionID = session.id
                        session.activeTabID = tab.id
                    }
                ))
            }
        }

        // Commands
        items.append(PaletteItem(
            id: "cmd-new-session",
            icon: "plus.rectangle",
            title: "New Session",
            subtitle: "Create a new terminal session",
            kind: .command,
            action: { appState.addSession() }
        ))
        items.append(PaletteItem(
            id: "cmd-new-tab",
            icon: "plus.square",
            title: "New Tab",
            subtitle: "Add a tab to current session",
            kind: .command,
            action: {
                if let session = appState.selectedSession {
                    let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
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
            action: {
                appState.selectedSession?.splitActiveTab(direction: .down)
            }
        ))
        items.append(PaletteItem(
            id: "cmd-settings",
            icon: "gear",
            title: "Open Settings",
            subtitle: "Configure SplitMux preferences",
            kind: .command,
            action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        ))

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
    let action: () -> Void

    enum PaletteItemKind {
        case session, tab, command
    }
}

struct PaletteItemRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(kindColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.8))

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()

            Text(kindLabel)
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.35))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color(white: 0.15) : .clear)
        .contentShape(Rectangle())
    }

    private var kindColor: Color {
        switch item.kind {
        case .session: return .green
        case .tab: return .blue
        case .command: return .orange
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .session: return "Session"
        case .tab: return "Tab"
        case .command: return "Command"
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
