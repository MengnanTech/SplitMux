import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: Session
    var onAddTab: () -> Void
    @State private var renamingTab: Tab?
    @State private var renameText = ""
    @State private var draggedTabID: UUID?

    private var barBg: Color { SettingsManager.shared.theme.tabBarBackground }
    private let dividerColor = Color(white: 0.2)

    var body: some View {
        HStack(spacing: 0) {
            // Tabs — equal width, fill the bar
            ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    dividerColor.frame(width: 1, height: 20)
                }

                TabItemView(
                    tab: tab,
                    index: index,
                    isActive: tab.id == session.activeTabID,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.1)) {
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
                .frame(maxWidth: .infinity)
                .opacity(draggedTabID == tab.id ? 0.4 : 1.0)
                .onDrag {
                    draggedTabID = tab.id
                    return NSItemProvider(object: tab.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    session: session,
                    targetTabID: tab.id,
                    draggedTabID: $draggedTabID
                ))
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

                    // Split options
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

            // Add button — fixed width on the right
            dividerColor.frame(width: 1, height: 20)

            Button(action: onAddTab) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(width: 40, height: 38)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
        .background(barBg)
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
        withAnimation {
            session.tabs.removeAll { $0.id != tab.id }
            session.activeTabID = tab.id
            session.splitRoot = nil
        }
    }

    private func closeTabsToRight(of tab: Tab) {
        guard let idx = session.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        withAnimation {
            session.tabs.removeSubrange((idx + 1)...)
            if let activeID = session.activeTabID,
               !session.tabs.contains(where: { $0.id == activeID }) {
                session.activeTabID = tab.id
            }
        }
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let session: Session
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedTabID,
              draggedID != targetTabID,
              let fromIndex = session.tabs.firstIndex(where: { $0.id == draggedID }),
              let toIndex = session.tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            session.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Close button area (left)
                ZStack {
                    if isActive || isHovered {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .contentShape(Circle())
                            .onTapGesture { onClose() }
                    }
                }
                .frame(width: 28)

                Spacer(minLength: 0)

                // Agent progress indicator
                if tab.claudeStatus == .running {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .padding(.trailing, 2)
                } else if tab.claudeStatus == .needsInput {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .padding(.trailing, 2)
                }

                // SSH connection indicator
                if tab.isSSH {
                    Image(systemName: "network")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                        .padding(.trailing, 2)
                }

                // Notification dot
                if tab.hasNotification && !isActive {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .padding(.trailing, 4)
                }

                // Title center
                Text(tabDisplayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(tab.hasNotification && !isActive ? Color.orange : (isActive ? .white : Color(white: 0.55)))
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Shortcut badge (right)
                if index < 9 {
                    Text("\u{2318}\(index + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: isActive ? 0.4 : 0.25))
                        .frame(width: 28)
                } else {
                    Spacer().frame(width: 28)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isActive
                          ? Color(white: 0.25)
                          : isHovered ? Color(white: 0.18) : Color.clear)
            )
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var tabDisplayTitle: String {
        if case .terminal = tab.content {
            return "~ (-\(tab.title))"
        }
        if case .sshTerminal = tab.content {
            return "ssh: \(tab.title)"
        }
        return tab.title
    }
}
