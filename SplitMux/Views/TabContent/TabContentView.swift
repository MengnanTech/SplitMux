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

            // Breadcrumb path bar
            BreadcrumbBar(workingDirectory: session.workingDirectory, gitBranch: session.gitBranch)

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
                // Determine which mode to show
                let splitTabIDs = session.splitRoot?.tabIDs ?? []
                let showSplit = session.splitRoot != nil
                    && session.zoomedTabID == nil
                    && splitTabIDs.contains(session.activeTabID ?? UUID())
                let showZoom = session.splitRoot != nil
                    && session.zoomedTabID != nil

                // Split pane mode — always kept alive if splitRoot exists.
                // Zoom is handled internally by HSplitContent/VSplitContent
                // (ratio adjustment) so terminal views never move between containers.
                if let root = session.splitRoot {
                    SplitPaneView(session: session, node: root)
                        .opacity(showSplit || showZoom ? 1 : 0)
                        .allowsHitTesting(showSplit || showZoom)
                }

                // No separate zoom view — handled within SplitPaneView via ratio

                // Non-split tabs — rendered individually, shown when active and not in split/zoom
                ForEach(session.tabs.filter { !splitTabIDs.contains($0.id) }) { tab in
                    let isVisible = tab.id == session.activeTabID && !showSplit && !showZoom
                    TabPanelView(tab: tab, workingDirectory: session.workingDirectory)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                }

                // Drop zone overlay for drag-to-split (passthrough for normal clicks)
                SplitDropZoneOverlay(session: session)
                    .allowsHitTesting(false)
            }

            // Terminal history panel
            if showHistory, let tabID = session.activeTabID {
                TerminalHistoryView(tabID: tabID, isVisible: $showHistory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(theme.contentBackground)
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
