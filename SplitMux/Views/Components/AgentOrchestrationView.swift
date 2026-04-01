import SwiftUI

/// Dashboard view for monitoring and managing multiple Claude Code agents
struct AgentOrchestrationView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var inputText: [UUID: String] = [:]

    private var hookService: ClaudeHookService { ClaudeHookService.shared }
    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
                Text("Agent Dashboard")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Summary bar
            HStack(spacing: 16) {
                StatusPill(count: hookService.runningCount, label: "Running", color: .blue)
                StatusPill(count: hookService.needsInputCount, label: "Needs Input", color: .orange)
                StatusPill(count: hookService.idleCount, label: "Idle", color: theme.tertiaryText)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider().overlay(theme.subtleBorder)

            if hookService.agentInfos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cpu")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.disabledText)
                    Text("No active agents")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(theme.iconDimmed)
                    Text("Start Claude Code in a terminal tab\nto see agents here")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.disabledText)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                // Agent list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(hookService.agentInfos) { agent in
                            AgentRow(
                                agent: agent,
                                tabTitle: liveTabTitle(for: agent.tabID),
                                sessionName: liveSessionName(for: agent.tabID),
                                inputText: Binding(
                                    get: { inputText[agent.tabID] ?? "" },
                                    set: { inputText[agent.tabID] = $0 }
                                ),
                                onSwitch: { switchToAgent(agent) },
                                onSendInput: { sendInput(to: agent) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Divider().overlay(theme.subtleBorder)

                // Recent notifications
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Events")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.iconDimmed)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(hookService.recentNotifications.prefix(10)) { notification in
                                HStack(spacing: 8) {
                                    Image(systemName: notification.status.icon)
                                        .font(.system(size: 9))
                                        .foregroundStyle(notification.status.color)

                                    Text(notification.message)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(theme.secondaryText)

                                    Spacer()

                                    Text(timeAgo(notification.timestamp))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(theme.disabledText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 520, height: 500)
        .background(theme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear {
            hookService.refreshAgentMetadata(from: appState)
        }
    }

    // MARK: - Actions

    private func switchToAgent(_ agent: AgentInfo) {
        if let sessionID = agent.sessionID {
            appState.selectedSessionID = sessionID
            if let session = appState.sessions.first(where: { $0.id == sessionID }) {
                session.activeTabID = agent.tabID
            }
        }
        isPresented = false
    }

    private func sendInput(to agent: AgentInfo) {
        guard let text = inputText[agent.tabID], !text.isEmpty else { return }

        // Find the terminal view and send input to the process
        for session in appState.sessions {
            if let tab = session.tabs.first(where: { $0.id == agent.tabID }),
               let termView = tab.terminalView as? NotifyingTerminalView {
                let bytes = Array((text + "\n").utf8)
                termView.send(data: bytes[...])
                inputText[agent.tabID] = ""
                break
            }
        }
    }

    private func liveTabTitle(for tabID: UUID) -> String {
        for session in appState.sessions {
            if let tab = session.tabs.first(where: { $0.id == tabID }) {
                return tab.title.isEmpty ? "Terminal" : tab.title
            }
        }
        return "Terminal"
    }

    private func liveSessionName(for tabID: UUID) -> String {
        for session in appState.sessions {
            if session.tabs.contains(where: { $0.id == tabID }) {
                return session.name
            }
        }
        return ""
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let count: Int
    let label: String
    let color: Color

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(count > 0 ? color : theme.disabledText)

            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(count > 0 ? color.opacity(0.1) : theme.hoverBackground.opacity(0.5))
        )
    }
}

// MARK: - Agent Row

struct AgentRow: View {
    let agent: AgentInfo
    let tabTitle: String
    let sessionName: String
    @Binding var inputText: String
    var onSwitch: () -> Void
    var onSendInput: () -> Void

    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Status icon with animation
                ZStack {
                    if agent.status == .running {
                        Circle()
                            .fill(agent.status.color.opacity(0.2))
                            .frame(width: 24, height: 24)

                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: agent.status.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(agent.status.color)
                            .frame(width: 24, height: 24)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tabTitle)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(theme.primaryText)

                        if !sessionName.isEmpty {
                            Text("in \(sessionName)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.iconDimmed)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(agent.toolDisplayText ?? agent.status.label)
                            .foregroundStyle(agent.status.color)
                        Text(agent.durationString)
                            .foregroundStyle(theme.disabledText)
                    }
                    .font(.system(.caption2, design: .monospaced))

                    if let error = agent.lastError, agent.status == .error {
                        Text(error)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Switch button
                Button(action: onSwitch) {
                    Text("Switch")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            // Input field for agents needing input
            if agent.status == .needsInput {
                HStack(spacing: 6) {
                    TextField("Send input to agent...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onSubmit { onSendInput() }

                    Button(action: onSendInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
                .padding(.leading, 34)
            }

            // Recent actions
            if !agent.recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(agent.recentActions.prefix(3)) { action in
                        HStack(spacing: 4) {
                            Image(systemName: action.success ? "checkmark" : "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(action.success ? theme.disabledText : .red)
                            Text(action.displayText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(action.success ? theme.disabledText : .red.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.hoverBackground.opacity(0.6))
        )
    }
}

// MARK: - Compact Agent Section for Sidebar

struct AgentsSidebarSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = true

    private var hookService: ClaudeHookService { ClaudeHookService.shared }
    private var theme: AppTheme { SettingsManager.shared.theme }

    var body: some View {
        if !hookService.agentInfos.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(theme.iconDimmed)
                                .frame(width: 10)

                            Text("Claude Agents")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.sectionHeaderText)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Quick status summary
                    HStack(spacing: 4) {
                        if hookService.runningCount > 0 {
                            HStack(spacing: 2) {
                                Circle().fill(Color.blue).frame(width: 5, height: 5)
                                Text("\(hookService.runningCount)")
                            }
                        }
                        if hookService.needsInputCount > 0 {
                            HStack(spacing: 2) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text("\(hookService.needsInputCount)")
                            }
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.sectionHeaderText)

                    Button {
                        NotificationCenter.default.post(name: .showAgentDashboard, object: nil)
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.iconDimmed)
                    }
                    .buttonStyle(.plain)
                    .help("Open Agent Dashboard")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if isExpanded {
                    LazyVStack(spacing: 1) {
                        ForEach(hookService.agentInfos) { agent in
                            HStack(spacing: 8) {
                                Image(systemName: agent.status.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(agent.status.color)

                                Text(liveTabTitle(for: agent.tabID))
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)

                                Spacer()

                                Text(agent.durationString)
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.disabledText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let sessionID = agent.sessionID {
                                    appState.selectedSessionID = sessionID
                                    appState.selectedSession?.activeTabID = agent.tabID
                                }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func liveTabTitle(for tabID: UUID) -> String {
        for session in appState.sessions {
            if let tab = session.tabs.first(where: { $0.id == tabID }) {
                return tab.title.isEmpty ? "Terminal" : tab.title
            }
        }
        return "Terminal"
    }
}
