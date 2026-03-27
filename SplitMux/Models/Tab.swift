import Foundation
import AppKit

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
    weak var terminalView: NSView?

    init(title: String, icon: String = "doc.text", content: TabContent = .text("")) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.content = content
        self.createdAt = Date()
    }

    static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum TabContent: Hashable {
    case text(String)
    case webURL(URL)
    case notes(String)
    case terminal
}
