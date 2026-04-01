import SwiftUI

struct TabContentView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showHistory = false
    @State private var draggedTabFrame: CGRect?

    private var theme: AppTheme { SettingsManager.shared.theme }
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — always visible for discoverability
            TabBarView(session: session, onAddTab: addTab)

            // Breadcrumb path bar
            BreadcrumbBar(
                workingDirectory: session.workingDirectory,
                gitBranch: session.gitBranch,
                claudeStatus: session.activeTab?.claudeStatus,
                claudeToolDetail: session.activeTab?.claudeToolDetail
            )

            // Content area with drag-to-split overlay
            ZStack(alignment: .topTrailing) {
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

                // Search bar — floating top-right like browser
                if showSearch {
                    TerminalSearchBar(
                        isVisible: $showSearch,
                        searchText: $searchText,
                        onSearch: { query, backward in
                            if let tv = session.activeTab?.terminalView as? NotifyingTerminalView {
                                return tv.searchTerminal(query: query, backward: backward)
                            }
                            return false
                        },
                        onDismiss: {
                            if let tv = session.activeTab?.terminalView as? NotifyingTerminalView {
                                tv.clearSearch()
                            }
                        }
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Terminal history panel
            if showHistory, let tabID = session.activeTabID {
                TerminalHistoryView(tabID: tabID, isVisible: $showHistory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "tabContentRoot")
        .onPreferenceChange(TabFrameKey.self) { frame in
            draggedTabFrame = frame
        }
        // Floating drag overlay — rendered above everything including terminal
        .overlay {
            if let frame = draggedTabFrame,
               let draggedID = session.tabDragState?.tabID,
               let tab = session.tabs.first(where: { $0.id == draggedID }),
               let index = session.tabs.firstIndex(where: { $0.id == draggedID }) {
                let state = session.tabDragState!
                ZStack {
                    TabItemView(
                        tab: tab,
                        index: index,
                        isActive: true,
                        onSelect: {},
                        onClose: {}
                    )
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.elevatedSurface)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .scaleEffect(state.isDraggingToSplit ? 0.88 : 1.0, anchor: .top)
                    .opacity(state.isDraggingToSplit ? 0.7 : 1.0)
                    .position(state.location)

                    // Split hint badge
                    if state.isDraggingToSplit {
                        Label(state.splitDirection.label, systemImage: state.splitDirection.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(theme.accentColor)
                                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                            )
                            .position(
                                x: state.location.x,
                                y: state.location.y + frame.height / 2 + 24
                            )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .background(theme.isGlass ? Color.clear : theme.contentBackground)
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalHistory)) { _ in
            guard session.id == appState.selectedSessionID else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalSearch)) { _ in
            guard session.id == appState.selectedSessionID else { return }
            withAnimation(.easeInOut(duration: 0.15)) { showSearch.toggle() }
        }
        // No full-view context menu overlay — terminal has its own right-click
        // menu via menu(for:), and the tab bar has per-tab context menus.
    }

    private func addTab() {
        let tab = session.createTab()
        withAnimation(.easeInOut(duration: 0.15)) {
            session.addTab(tab)
        }
    }
}
