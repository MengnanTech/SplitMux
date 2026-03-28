import SwiftUI

/// Recursive split pane view that renders a SplitNode tree
struct SplitPaneView: View {
    @Environment(AppState.self) private var appState
    let session: Session
    let node: SplitNode

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        // Zoom mode — show only the zoomed pane at full size (handled here
        // so the terminal view stays in the same SplitPaneView hierarchy
        // and never needs to move between containers).
        if let zoomedID = session.zoomedTabID,
           let zoomedTab = session.tabs.first(where: { $0.id == zoomedID }) {
            ZStack(alignment: .topTrailing) {
                splitTabPanel(tab: zoomedTab)

                FloatingZoomButton {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        session.toggleZoom()
                    }
                }
                .frame(width: 28, height: 28)
                .padding(10)
            }
        } else {
            switch node {
            case .tab(let tabID):
                if let tab = session.tabs.first(where: { $0.id == tabID }) {
                    splitTabPanel(tab: tab)
                } else {
                    theme.contentBackground
                }

            case .horizontal(let first, let second, let ratio):
                HSplitContent(
                    session: session,
                    first: first,
                    second: second,
                    ratio: ratio
                )

            case .vertical(let first, let second, let ratio):
                VSplitContent(
                    session: session,
                    first: first,
                    second: second,
                    ratio: ratio
                )
            }
        }
    }

    @ViewBuilder
    private func splitTabPanel(tab: Tab) -> some View {
        let isActive = tab.id == session.activeTabID

        TabPanelView(tab: tab, workingDirectory: session.workingDirectory)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isActive ? theme.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
                    .padding(1)
            )
            .overlay(alignment: .topTrailing) {
                if let status = tab.claudeStatus, status != .unknown {
                    SplitPaneStatusBadge(status: status, hasNotification: tab.hasNotification)
                        .padding(8)
                }
            }
            // Pane click-to-focus is handled by NotifyingTerminalView.onPaneClicked
            // Double-click zoom via ⌘⇧Z keyboard shortcut
    }
}

/// Horizontal split with draggable divider
struct HSplitContent: View {
    @Environment(AppState.self) private var appState
    let session: Session
    let first: SplitNode
    let second: SplitNode
    let ratio: Double

    @State private var currentRatio: Double
    @State private var isDividerHovered = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    init(session: Session, first: SplitNode, second: SplitNode, ratio: Double) {
        self.session = session
        self.first = first
        self.second = second
        self.ratio = ratio
        self._currentRatio = State(initialValue: ratio)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SplitPaneView(session: session, node: first)
                    .frame(width: geo.size.width * currentRatio - 2)

                // Draggable divider with hover highlight
                Rectangle()
                    .fill(isDividerHovered ? theme.splitDividerHover : theme.splitDivider)
                    .frame(width: isDividerHovered ? 6 : 4)
                    .animation(.easeInOut(duration: 0.12), value: isDividerHovered)
                    .onHover { hovering in
                        isDividerHovered = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newRatio = max(0.15, min(0.85, Double(value.location.x / geo.size.width)))
                                currentRatio = newRatio
                            }
                            .onEnded { _ in
                                updateSessionRatio()
                            }
                    )

                SplitPaneView(session: session, node: second)
            }
        }
    }

    private func updateSessionRatio() {
        if let root = session.splitRoot {
            session.splitRoot = updateRatioInTree(root, target: (first, second), newRatio: currentRatio)
        }
    }

    private func updateRatioInTree(_ node: SplitNode, target: (SplitNode, SplitNode), newRatio: Double) -> SplitNode {
        switch node {
        case .horizontal(let a, let b, _) where a == target.0 && b == target.1:
            return .horizontal(a, b, ratio: newRatio)
        case .horizontal(let a, let b, let r):
            return .horizontal(
                updateRatioInTree(a, target: target, newRatio: newRatio),
                updateRatioInTree(b, target: target, newRatio: newRatio),
                ratio: r
            )
        case .vertical(let a, let b, let r):
            return .vertical(
                updateRatioInTree(a, target: target, newRatio: newRatio),
                updateRatioInTree(b, target: target, newRatio: newRatio),
                ratio: r
            )
        default:
            return node
        }
    }
}

/// Vertical split with draggable divider
struct VSplitContent: View {
    @Environment(AppState.self) private var appState
    let session: Session
    let first: SplitNode
    let second: SplitNode
    let ratio: Double

    @State private var currentRatio: Double
    @State private var isDividerHovered = false

    private var theme: AppTheme { SettingsManager.shared.theme }

    init(session: Session, first: SplitNode, second: SplitNode, ratio: Double) {
        self.session = session
        self.first = first
        self.second = second
        self.ratio = ratio
        self._currentRatio = State(initialValue: ratio)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                SplitPaneView(session: session, node: first)
                    .frame(height: geo.size.height * currentRatio - 2)

                Rectangle()
                    .fill(isDividerHovered ? theme.splitDividerHover : theme.splitDivider)
                    .frame(height: isDividerHovered ? 6 : 4)
                    .animation(.easeInOut(duration: 0.12), value: isDividerHovered)
                    .onHover { hovering in
                        isDividerHovered = hovering
                        if hovering {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newRatio = max(0.15, min(0.85, Double(value.location.y / geo.size.height)))
                                currentRatio = newRatio
                            }
                            .onEnded { _ in
                                updateSessionRatio()
                            }
                    )

                SplitPaneView(session: session, node: second)
            }
        }
    }

    private func updateSessionRatio() {
        if let root = session.splitRoot {
            session.splitRoot = updateRatioInTree(root, target: (first, second), newRatio: currentRatio)
        }
    }

    private func updateRatioInTree(_ node: SplitNode, target: (SplitNode, SplitNode), newRatio: Double) -> SplitNode {
        switch node {
        case .vertical(let a, let b, _) where a == target.0 && b == target.1:
            return .vertical(a, b, ratio: newRatio)
        case .horizontal(let a, let b, let r):
            return .horizontal(
                updateRatioInTree(a, target: target, newRatio: newRatio),
                updateRatioInTree(b, target: target, newRatio: newRatio),
                ratio: r
            )
        case .vertical(let a, let b, let r):
            return .vertical(
                updateRatioInTree(a, target: target, newRatio: newRatio),
                updateRatioInTree(b, target: target, newRatio: newRatio),
                ratio: r
            )
        default:
            return node
        }
    }
}

/// Floating status badge shown on each split pane
struct SplitPaneStatusBadge: View {
    let status: ClaudeStatus
    let hasNotification: Bool

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(status.color)
            }

            Text(status.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(status.color)

            if hasNotification {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.elevatedSurface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(status.color.opacity(0.3), lineWidth: 0.5)
                )
        )
        .allowsHitTesting(false)
    }
}
