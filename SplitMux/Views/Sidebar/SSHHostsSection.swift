import SwiftUI

/// Sidebar section showing SSH hosts with connect/manage actions
struct SSHHostsSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = true
    @State private var showAddHost = false
    @State private var editingHost: SSHHost?
    @State private var hoveredHostID: UUID?

    private let sshManager = SSHManagerService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(white: 0.4))
                            .frame(width: 10)

                        Text("SSH Hosts")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(white: 0.5))
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    // Refresh config button
                    Button {
                        sshManager.refreshConfig()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh ~/.ssh/config")

                    // Add host button
                    Button { showAddHost = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isExpanded {
                if sshManager.allHosts.isEmpty {
                    Text("No SSH hosts")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(sshManager.allHosts) { host in
                            SSHHostRow(
                                host: host,
                                isHovered: hoveredHostID == host.id,
                                onConnect: { connectToHost(host) },
                                onEdit: { editingHost = host }
                            )
                            .onHover { hovering in
                                hoveredHostID = hovering ? host.id : nil
                            }
                            .contextMenu {
                                Button("Connect") { connectToHost(host) }

                                Button("Edit...") { editingHost = host }

                                if sshManager.savedHosts.contains(where: { $0.id == host.id }) {
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        sshManager.removeHost(host.id)
                                    }
                                } else {
                                    Button("Save to Favorites") {
                                        sshManager.addHost(host)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
        }
        .sheet(isPresented: $showAddHost) {
            SSHHostEditorView(
                host: SSHHost(),
                isNew: true,
                onSave: { host in
                    sshManager.addHost(host)
                    showAddHost = false
                },
                onCancel: { showAddHost = false }
            )
        }
        .sheet(item: $editingHost) { host in
            SSHHostEditorView(
                host: host,
                isNew: false,
                onSave: { _ in
                    sshManager.updateHost(host)
                    editingHost = nil
                },
                onCancel: { editingHost = nil }
            )
        }
    }

    private func connectToHost(_ host: SSHHost) {
        guard let session = appState.selectedSession else { return }
        let tab = Tab(
            title: host.displayName,
            icon: "network",
            content: .sshTerminal(hostID: host.id)
        )
        tab.sshHostID = host.id
        host.lastConnected = Date()
        sshManager.updateHost(host)

        withAnimation(.easeInOut(duration: 0.15)) {
            session.addTab(tab)
        }
    }
}

// MARK: - SSH Host Row

struct SSHHostRow: View {
    let host: SSHHost
    let isHovered: Bool
    var onConnect: () -> Void
    var onEdit: () -> Void

    private var bgColor: Color {
        isHovered ? Color(white: 0.15) : .clear
    }

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 8) {
                // Color tag + status dot
                ZStack {
                    Circle()
                        .fill(host.colorTag.color)
                        .frame(width: 8, height: 8)

                    if host.connectionState == .connected {
                        Circle()
                            .stroke(Color.green, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(host.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(white: 0.75))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if !host.username.isEmpty {
                            Text("\(host.username)@\(host.hostname)")
                        } else {
                            Text(host.hostname)
                        }
                        if host.port != 22 {
                            Text(":\(host.port)")
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                    .lineLimit(1)
                }

                Spacer()

                // Connection state indicator
                Image(systemName: host.connectionState.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(host.connectionState.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
