import SwiftUI

struct TabContentView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showHistory = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — always visible for discoverability
            TabBarView(session: session, onAddTab: addTab)

            // Breadcrumb path bar + zoom indicator
            HStack(spacing: 0) {
                BreadcrumbBar(workingDirectory: session.workingDirectory, gitBranch: session.gitBranch)

                if session.splitRoot != nil, session.zoomedTabID != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            session.toggleZoom()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 9))
                            Text("ZOOM")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(theme.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(theme.accentColor.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                }
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

            // Content area with drag-to-split overlay
            ZStack {
                if let root = session.splitRoot, session.zoomedTabID == nil {
                    // Split pane mode
                    SplitPaneView(session: session, node: root)
                } else if session.splitRoot != nil, let zoomedID = session.zoomedTabID,
                          let zoomedTab = session.tabs.first(where: { $0.id == zoomedID }) {
                    // Zoomed pane mode — single pane fills area
                    TabPanelView(tab: zoomedTab, workingDirectory: session.workingDirectory)
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

                // Drop zone overlay for drag-to-split
                SplitDropZoneOverlay(session: session)
            }

            // Terminal history panel
            if showHistory, let tabID = session.activeTabID {
                TerminalHistoryView(tabID: tabID, isVisible: $showHistory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(SettingsManager.shared.theme.contentBackground)
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalHistory)) { _ in
            guard session.id == appState.selectedSessionID else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalSearch)) { _ in
            guard session.id == appState.selectedSessionID else { return }
            withAnimation(.easeInOut(duration: 0.15)) { showSearch.toggle() }
        }
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
