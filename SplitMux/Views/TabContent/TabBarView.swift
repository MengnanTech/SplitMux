import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    var onAddTab: () -> Void
    @State private var renamingTab: Tab?
    @State private var renameText = ""
    @State private var draggedTabID: UUID?
    @State private var lastSwapX: CGFloat = 0

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
                        session.activeTabID = tab.id
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
                .frame(maxWidth: 200)
                .gesture(
                    DragGesture(coordinateSpace: .named("tabBar"))
                        .onChanged { value in
                            draggedTabID = tab.id
                            let delta = value.translation.width - lastSwapX
                            if delta > 100,
                               let i = session.tabs.firstIndex(where: { $0.id == tab.id }),
                               i < session.tabs.count - 1 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    session.tabs.swapAt(i, i + 1)
                                }
                                lastSwapX = value.translation.width
                            } else if delta < -100,
                                      let i = session.tabs.firstIndex(where: { $0.id == tab.id }),
                                      i > 0 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    session.tabs.swapAt(i, i - 1)
                                }
                                lastSwapX = value.translation.width
                            }
                        }
                        .onEnded { _ in
                            draggedTabID = nil
                            lastSwapX = 0
                        }
                )
                .contextMenu {
                    Button {
                        renameText = tab.title
                        renamingTab = tab
                    } label: {
                        Label("Rename Tab", systemImage: "pencil")
                    }

                    Button {
                        let newTab = Tab(title: "\(tab.title) Copy", icon: tab.icon, content: tab.content)
                        withAnimation { session.addTab(newTab) }
                    } label: {
                        Label("Duplicate Tab", systemImage: "doc.on.doc")
                    }

                    Divider()

                    ForEach(SplitDirection.allCases, id: \.rawValue) { direction in
                        Button {
                            session.activeTabID = tab.id
                            withAnimation(.easeInOut(duration: 0.2)) {
                                session.splitActiveTab(direction: direction)
                            }
                        } label: {
                            Label(direction.label, systemImage: direction.icon)
                        }
                    }

                    Divider()

                    Button {
                        closeOtherTabs(keep: tab)
                    } label: {
                        Label("Close Other Tabs", systemImage: "xmark.square")
                    }
                    .disabled(session.tabs.count <= 1)

                    Button {
                        closeTabsToRight(of: tab)
                    } label: {
                        Label("Close Tabs to the Right", systemImage: "arrow.right.to.line")
                    }
                    .disabled(tab.id == session.tabs.last?.id)

                    Divider()

                    Button(role: .destructive) {
                        withAnimation { session.removeTab(tab.id) }
                    } label: {
                        Label("Close Tab", systemImage: "xmark")
                    }
                }
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
        .coordinateSpace(name: "tabBar")
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
            ZStack {
                if isActive || isHovered {
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
                }
            }
            .frame(width: 26)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.accentColor.opacity(usesLightChrome ? 0.1 : 0.2))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.hoverBackground.opacity(0.4))
                }
            }
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
