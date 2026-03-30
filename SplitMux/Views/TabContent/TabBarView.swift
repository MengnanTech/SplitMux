import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    var onAddTab: () -> Void
    @State private var renamingTab: Tab?
    @State private var renameText = ""
    @State private var draggedTabID: UUID?
    @State private var tabCenters: [UUID: CGFloat] = [:]
    @State private var lastSwapTime: Date = .distantPast
    /// +1 = last swap was rightward, -1 = leftward, 0 = none
    @State private var lastSwapDirection: Int = 0

    private var theme: AppTheme { SettingsManager.shared.theme }
    private var usesLightChrome: Bool {
        if case .light = theme { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    theme.subtleBorder.opacity(0.5).frame(width: 1, height: 18)
                }

                TabItemView(
                    tab: tab,
                    index: index,
                    isActive: tab.id == session.activeTabID,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            session.activeTabID = tab.id
                        }
                        tab.hasNotification = false
                        tab.lastNotificationMessage = nil
                        appState.updateDockBadge()
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            session.removeTab(tab.id)
                        }
                    }
                )
                .overlay(
                    NativeContextMenu { self.buildTabMenu(tab: tab) }
                )
                .frame(maxWidth: 200)
                // Invisible placeholder keeps layout space; floating overlay
                // in TabContentView renders the visible dragged tab.
                .opacity(draggedTabID == tab.id ? 0 : 1.0)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: TabFrameKey.self,
                                value: draggedTabID == tab.id
                                    ? geo.frame(in: .named("tabContentRoot"))
                                    : nil
                            )
                            .onAppear {
                                tabCenters[tab.id] = geo.frame(in: .named("tabContentRoot")).midX
                            }
                            .onChange(of: geo.frame(in: .named("tabContentRoot")).midX) { _, newX in
                                tabCenters[tab.id] = newX
                            }
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("tabContentRoot"))
                        .onChanged { value in
                            draggedTabID = tab.id
                            let dx = value.translation.width
                            let dy = value.translation.height

                            session.tabDragState = TabDragState(
                                tabID: tab.id,
                                location: value.location,
                                translation: CGSize(width: dx, height: dy),
                                isDraggingToSplit: dy > 30,
                                splitDirection: dx > 80 ? .right : (dx < -80 ? .left : .down)
                            )

                            // Position-based reorder with hysteresis:
                            // - Forward (same direction as last swap): 30% threshold
                            // - Reverse (opposite direction): must cross neighbor's center (60%)
                            // This prevents back-and-forth shuttling near boundaries.
                            guard dy <= 30,
                                  Date().timeIntervalSince(lastSwapTime) > 0.2
                            else { return }
                            let fingerX = value.location.x
                            guard let fromIndex = session.tabs.firstIndex(where: { $0.id == tab.id }) else { return }

                            // Check right swap
                            if fromIndex < session.tabs.count - 1 {
                                let rightNeighborID = session.tabs[fromIndex + 1].id
                                if let rightCx = tabCenters[rightNeighborID],
                                   let myCx = tabCenters[tab.id] {
                                    // Tighter threshold if reversing direction
                                    let ratio: CGFloat = lastSwapDirection == -1 ? 0.6 : 0.3
                                    let edge = myCx + (rightCx - myCx) * ratio
                                    if fingerX > edge {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            session.tabs.swapAt(fromIndex, fromIndex + 1)
                                        }
                                        lastSwapTime = Date()
                                        lastSwapDirection = 1
                                        return
                                    }
                                }
                            }
                            // Check left swap
                            if fromIndex > 0 {
                                let leftNeighborID = session.tabs[fromIndex - 1].id
                                if let leftCx = tabCenters[leftNeighborID],
                                   let myCx = tabCenters[tab.id] {
                                    let ratio: CGFloat = lastSwapDirection == 1 ? 0.6 : 0.3
                                    let edge = myCx - (myCx - leftCx) * ratio
                                    if fingerX < edge {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            session.tabs.swapAt(fromIndex, fromIndex - 1)
                                        }
                                        lastSwapTime = Date()
                                        lastSwapDirection = -1
                                        return
                                    }
                                }
                            }
                        }
                        .onEnded { _ in
                            if let state = session.tabDragState, state.isDraggingToSplit {
                                let dir = state.splitDirection
                                let tabID = tab.id
                                Task { @MainActor in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        session.activeTabID = tabID
                                        session.splitActiveTab(direction: dir)
                                    }
                                }
                            }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                draggedTabID = nil
                                session.tabDragState = nil
                                lastSwapDirection = 0
                            }
                        }
                )
            }

            // Add button
            Button(action: onAddTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            WindowDragArea()
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
        }
        .frame(height: 38)
        .background(.clear)
        .overlay(alignment: .bottom) {
            if usesLightChrome {
                theme.subtleBorder.opacity(0.45).frame(height: 0.5)
            }
        }
        .alert("Rename Tab", isPresented: Binding(
            get: { renamingTab != nil },
            set: { if !$0 { renamingTab = nil } }
        )) {
            TextField("Tab name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let tab = renamingTab, !renameText.isEmpty {
                    tab.title = renameText
                }
                renamingTab = nil
            }
        }
    }

    private func closeOtherTabs(keep tab: Tab) {
        let idsToRemove = session.tabs.filter { $0.id != tab.id }.map(\.id)
        withAnimation {
            for id in idsToRemove {
                session.removeTab(id)
            }
            session.activeTabID = tab.id
            session.splitRoot = nil
        }
    }

    private func closeTabsToRight(of tab: Tab) {
        guard let idx = session.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let idsToRemove = session.tabs[(idx + 1)...].map(\.id)
        withAnimation {
            for id in idsToRemove {
                session.removeTab(id)
            }
            if let activeID = session.activeTabID,
               !session.tabs.contains(where: { $0.id == activeID }) {
                session.activeTabID = tab.id
            }
        }
    }

    private func buildTabMenu(tab: Tab) -> NSMenu {
        let menu = NSMenu()

        menu.addActionItem("Rename Tab", image: "pencil") {
            self.renameText = tab.title
            self.renamingTab = tab
        }

        menu.addActionItem("Duplicate Tab", image: "doc.on.doc") {
            let newTab = Tab(title: "\(tab.title) Copy", icon: tab.icon, content: tab.content)
            withAnimation { self.session.addTab(newTab) }
        }

        menu.addItem(.separator())

        for direction in SplitDirection.allCases {
            menu.addActionItem(direction.label, image: direction.icon) {
                Task { @MainActor in
                    self.session.activeTabID = tab.id
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.session.splitActiveTab(direction: direction)
                    }
                }
            }
        }

        menu.addItem(.separator())

        menu.addActionItem("Close Other Tabs", image: "xmark.square", enabled: session.tabs.count > 1) {
            self.closeOtherTabs(keep: tab)
        }

        menu.addActionItem("Close Tabs to the Right", image: "arrow.right.to.line", enabled: tab.id != self.session.tabs.last?.id) {
            self.closeTabsToRight(of: tab)
        }

        menu.addItem(.separator())

        menu.addActionItem("Close Tab", image: "xmark") {
            withAnimation { self.session.removeTab(tab.id) }
        }

        return menu
    }

    @ViewBuilder
    private func lightChromeCapsule(shadowOpacity: Double = 0.14) -> some View {
        Capsule(style: .continuous)
            .fill(theme.chromeSurfaceBackground)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(theme.subtleBorder.opacity(0.35), lineWidth: 0.6)
            )
            .shadow(color: theme.chromeShadow.opacity(shadowOpacity), radius: 1.5, y: 0.5)
    }
}

// MARK: - Tab Item View

struct TabItemView: View {
    let tab: Tab
    let index: Int
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovered = false
    private var theme: AppTheme { SettingsManager.shared.theme }
    private var usesLightChrome: Bool {
        if case .light = theme { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            // Shortcut badge
            if index < 9 {
                Text("\u{2318}\(index + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? theme.tertiaryText : theme.disabledText)
                    .frame(width: 26)
            } else {
                Spacer().frame(width: 26)
            }

            Spacer(minLength: 0)

            // Status indicators
            if tab.claudeStatus == .running {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .padding(.trailing, 3)
            } else if tab.claudeStatus == .needsInput {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .padding(.trailing, 3)
            }

            if tab.isSSH {
                Image(systemName: "network")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .padding(.trailing, 3)
            }

            // Notification dot
            if tab.hasNotification && !isActive {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 4)
            }

            // Title
            Text(tabDisplayTitle)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(
                    tab.hasNotification && !isActive
                    ? Color.orange
                    : (isActive ? theme.primaryText : theme.secondaryText)
                )
                .lineLimit(1)

            Spacer(minLength: 0)

            // Close button
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.subtleOverlay)
                )
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .opacity(isActive || isHovered ? 1 : 0)
                .allowsHitTesting(isActive || isHovered)
                .frame(width: 26)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isActive ? theme.accentColor.opacity(usesLightChrome ? 0.1 : 0.2) :
                    isHovered ? theme.hoverBackground.opacity(0.4) :
                    Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var tabDisplayTitle: String {
        if case .terminal = tab.content {
            return tab.title
        }
        if case .sshTerminal = tab.content {
            return "ssh: \(tab.title)"
        }
        return tab.title
    }

    @ViewBuilder
    private func lightChromeCapsule() -> some View {
        Capsule(style: .continuous)
            .fill(theme.chromeSurfaceBackground)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(theme.subtleBorder.opacity(0.28), lineWidth: 0.6)
            )
            .shadow(color: theme.chromeShadow.opacity(0.14), radius: 2.5, y: 1)
    }
}

// MARK: - Preference key for tab frame (used for floating drag overlay)

struct TabFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
