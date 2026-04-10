import Foundation
import AppKit

@MainActor
@Observable
class Tab: Identifiable, Hashable {
    let id: UUID
    var title: String
    var icon: String
    var content: TabContent
    var createdAt: Date
    var hasNotification: Bool = false
    var lastNotificationMessage: String?
    var claudeStatus: ClaudeStatus?
    var claudeToolDetail: String?
    /// Strong reference — terminal view must survive SwiftUI view recreation
    /// (e.g. split mode transitions) to preserve running process & Claude detection state.
    /// Cleaned up when tab is removed via Session.removeTab().
    var terminalView: NSView?

    /// SSH host ID for SSH terminal tabs
    var sshHostID: UUID?

    init(id: UUID = UUID(), title: String, icon: String = "doc.text", content: TabContent = .text("")) {
        self.id = id
        self.title = title
        self.icon = icon
        self.content = content
        self.createdAt = Date()
    }

    nonisolated static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Whether this tab is an SSH connection
    var isSSH: Bool {
        if case .sshTerminal = content { return true }
        return false
    }
}

enum TabContent: Hashable {
    case text(String)
    case webURL(URL)
    case notes(String)
    case terminal
    case sshTerminal(hostID: UUID)
}
