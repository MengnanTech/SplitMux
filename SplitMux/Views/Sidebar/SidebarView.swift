import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredSessionID: UUID?
    @State private var renamingSession: Session?
    @State private var renameText = ""
    @State private var draggedSessionID: UUID?

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.sectionHeaderText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                Button {
                    appState.addSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.iconDimmed)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.subtleOverlay.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(theme.subtleBorder.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 36) // Space for traffic light buttons in fullSizeContentView
            .padding(.bottom, 10)

            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == appState.selectedSessionID,
                            isHovered: session.id == hoveredSessionID
                        )
                        .opacity(draggedSessionID == session.id ? 0.4 : 1.0)
                        .onTapGesture {
                            appState.selectedSessionID = session.id
                            if let activeTab = session.activeTab {
                                activeTab.hasNotification = false
                                activeTab.lastNotificationMessage = nil
                            }
                            appState.updateDockBadge()
                        }
                        .onHover { hovering in
                            hoveredSessionID = hovering ? session.id : nil
                        }
                        .onDrag {
                            draggedSessionID = session.id
                            return NSItemProvider(object: session.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: SessionDropDelegate(
                            appState: appState,
                            targetSessionID: session.id,
                            draggedSessionID: $draggedSessionID
                        ))
                        .contextMenu {
                            Button {
                                let tab = Tab(title: "Terminal", icon: "terminal", content: .terminal)
                                session.addTab(tab)
                            } label: {
                                Label("New Tab", systemImage: "plus.square")
                            }

                            Button {
                                pickWorkingDirectory(for: session)
                            } label: {
                                Label("Set Working Directory...", systemImage: "folder")
                            }

                            Button {
                                renameText = session.customName ?? ""
                                renamingSession = session
                            } label: {
                                Label("Rename...", systemImage: "pencil")
                            }

                            Button("Duplicate") {
                                duplicateSession(session)
                            }

                            Divider()

                            ForEach(SplitDirection.allCases, id: \.rawValue) { direction in
                                Button {
                                    appState.selectedSessionID = session.id
                                    withAnimation {
                                        session.splitActiveTab(direction: direction)
                                    }
                                } label: {
                                    Label(direction.label, systemImage: direction.icon)
                                }
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                withAnimation {
                                    appState.removeSession(session.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            // Subtle divider above bottom sections
            theme.subtleBorder.opacity(0.4)
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Claude Agents section
            AgentsSidebarSection()

            // SSH Hosts section
            SSHHostsSection()

            // Footer
            HStack(spacing: 5) {
                Image(systemName: "command")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.iconDimmed)
                Text("P")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.iconDimmed)
                Text("Command Palette")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)

                Spacer()

                Text("\(appState.sessions.count) sessions")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                // Base gradient for depth
                theme.sidebarGradient

                // Frosted glass overlay
                theme.chromeOverlay

                // Shared canvas material beneath the sidebar shell
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.subtleBorder.opacity(0.45))
                .frame(width: 0.5)
        }
        .alert("Rename Session", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Name (empty = use folder name)", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let session = renamingSession {
                    session.customName = renameText.isEmpty ? nil : renameText
                }
                renamingSession = nil
            }
        }
    }

    private func pickWorkingDirectory(for session: Session) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose working directory for \"\(session.name)\""
        panel.directoryURL = URL(fileURLWithPath: session.workingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            session.workingDirectory = url.path

            if session.tabs.count == 1,
               let tab = session.tabs.first,
               let tv = tab.terminalView as? NotifyingTerminalView {
                tv.sessionDelegate?.suppressNextNotification = true
                tv.restartProcess(in: url.path)
            }
        }
    }

    private func duplicateSession(_ session: Session) {
        let newSession = Session(
            name: session.customName,
            icon: session.icon,
            workingDirectory: session.workingDirectory
        )
        for tab in session.tabs {
            let newTab = Tab(title: tab.title, icon: tab.icon, content: tab.content)
            newSession.addTab(newTab)
        }
        newSession.startGitBranchPolling()
        appState.sessions.append(newSession)
        appState.selectedSessionID = newSession.id
        appState.scheduleSave()
    }
}

// MARK: - Session Drop Delegate

struct SessionDropDelegate: DropDelegate {
    let appState: AppState
    let targetSessionID: UUID
    @Binding var draggedSessionID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedSessionID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedSessionID,
              draggedID != targetSessionID,
              let fromIndex = appState.sessions.firstIndex(where: { $0.id == draggedID }),
              let toIndex = appState.sessions.firstIndex(where: { $0.id == targetSessionID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            appState.sessions.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let isHovered: Bool

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: session.icon)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accentColor : theme.tertiaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.bodyText)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                    Text(session.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let branch = session.gitBranch {
                        Text("·")
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 7))
                        Text(branch)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)

                // Per-tab Claude status indicators
                let claudeTabs = session.claudeTabs
                if !claudeTabs.isEmpty {
                    ForEach(claudeTabs, id: \.tab.id) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.status.icon)
                                .font(.system(size: 8))
                            Text(claudeTabs.count > 1 ? "\(item.tab.title): \(item.status.label)" : item.status.label)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(item.status.color)
                    }
                }

                // Notification message preview
                if let msg = session.latestNotificationMessage, session.claudeStatus == nil {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Notification badge
            if session.notificationCount > 0 {
                Text("\(session.notificationCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    // Softer selection wash that stays close to the shared canvas
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.chromeSurfaceBackground.opacity(0.94),
                                    theme.accentColor.opacity(0.10),
                                    theme.accentColor.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    theme.accentColor.opacity(0.14),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: theme.chromeShadow.opacity(0.09), radius: 4, y: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.hoverBackground.opacity(0.6))
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
