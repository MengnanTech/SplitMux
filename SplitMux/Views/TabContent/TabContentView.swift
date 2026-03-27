import SwiftUI

struct TabContentView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    @State private var showSearch = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (hidden when single tab and no split)
            if session.tabs.count > 1 || session.splitRoot != nil {
                TabBarView(session: session, onAddTab: addTab)
            }

            // Search bar overlay
            if showSearch {
                TerminalSearchBar(
                    isVisible: $showSearch,
                    searchText: $searchText,
                    onSearch: { query, backward in
                        if let tv = session.activeTab?.terminalView as? NotifyingTerminalView {
                            tv.searchTerminal(query: query, backward: backward)
                        }
                    },
                    onDismiss: {}
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Content area
            if let root = session.splitRoot {
                // Split pane mode
                SplitPaneView(session: session, node: root)
            } else {
                // Single tab mode
                ZStack {
                    ForEach(session.tabs) { tab in
                        TabPanelView(tab: tab, workingDirectory: session.workingDirectory)
                            .opacity(tab.id == session.activeTabID ? 1 : 0)
                            .allowsHitTesting(tab.id == session.activeTabID)
                    }
                }
            }
        }
        .background(SettingsManager.shared.theme.contentBackground)
        .contextMenu {
            Button {
                addTab()
            } label: {
                Label("New Tab", systemImage: "plus")
            }

            Divider()

            ForEach(SplitDirection.allCases, id: \.rawValue) { direction in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        session.splitActiveTab(direction: direction)
                    }
                } label: {
                    Label(direction.label, systemImage: direction.icon)
                }
            }

            if session.splitRoot != nil {
                Divider()
                Button("Unsplit") {
                    withAnimation {
                        session.unsplit()
                    }
                }
            }
        }
    }

    private func addTab() {
        let tab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        withAnimation(.easeInOut(duration: 0.15)) {
            session.addTab(tab)
        }
    }
}
