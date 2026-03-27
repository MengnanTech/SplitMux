import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredSessionID: UUID?
    @State private var renamingSession: Session?
    @State private var renameText = ""

    private let sidebarBg = Color(red: 0.1, green: 0.1, blue: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(white: 0.5))
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer()

                Button {
                    appState.addSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == appState.selectedSessionID,
                            isHovered: session.id == hoveredSessionID
                        )
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.12)) {
                                appState.selectedSessionID = session.id
                            }
                            // Clear notifications for active tab
                            if let activeTab = session.activeTab {
                                activeTab.hasNotification = false
                                activeTab.lastNotificationMessage = nil
                            }
                            appState.updateDockBadge()
                        }
                        .onHover { hovering in
                            hoveredSessionID = hovering ? session.id : nil
                        }
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

            Spacer()

            // Footer
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("\(appState.sessions.count) sessions")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(sidebarBg)
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

            // Restart terminal in the new directory (seamless, no visible cd)
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
        appState.sessions.append(newSession)
    }
}

struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let isHovered: Bool

    private var bgColor: Color {
        if isSelected {
            return Color(red: 0.18, green: 0.2, blue: 0.25)
        } else if isHovered {
            return Color(white: 0.15)
        }
        return .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.green : Color(white: 0.45))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(.callout, design: .default))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : Color(white: 0.7))

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                    Text(session.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))

                // Claude status indicator
                if let status = session.claudeStatus {
                    HStack(spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.system(size: 8))
                        Text(status.label)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(status.color)
                }

                // Notification message preview
                if let msg = session.latestNotificationMessage, session.claudeStatus == nil {
                    Text(msg)
                        .font(.system(.caption2, design: .monospaced))
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

            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green)
                    .frame(width: 3, height: 24)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
