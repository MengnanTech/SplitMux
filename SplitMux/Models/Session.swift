import Foundation

@Observable
class Session: Identifiable, Hashable {
    let id: UUID
    var customName: String?
    var icon: String
    var tabs: [Tab]
    var activeTabID: UUID?
    var createdAt: Date
    var workingDirectory: String

    /// Display name: custom name > folder name
    var name: String {
        get {
            if let custom = customName, !custom.isEmpty {
                return custom
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if workingDirectory == home {
                return "~"
            }
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }
        set {
            customName = newValue
        }
    }

    init(name: String? = nil, icon: String = "terminal", tabs: [Tab] = [], workingDirectory: String? = nil) {
        self.id = UUID()
        self.customName = name
        self.icon = icon
        self.tabs = tabs
        self.createdAt = Date()
        self.activeTabID = tabs.first?.id
        self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if workingDirectory == home {
            return "~"
        } else if workingDirectory.hasPrefix(home) {
            return "~" + workingDirectory.dropFirst(home.count)
        }
        return workingDirectory
    }

    var notificationCount: Int {
        tabs.filter(\.hasNotification).count
    }

    var latestNotificationMessage: String? {
        tabs.compactMap(\.lastNotificationMessage).last
    }

    /// Aggregate Claude status across all tabs (prioritizes running > needs-input > idle)
    var claudeStatus: ClaudeStatus? {
        let statuses = tabs.compactMap(\.claudeStatus)
        if statuses.isEmpty { return nil }
        if statuses.contains(.running) { return .running }
        if statuses.contains(.needsInput) { return .needsInput }
        if statuses.contains(.idle) { return .idle }
        return nil
    }

    func addTab(_ tab: Tab) {
        tabs.append(tab)
        activeTabID = tab.id
    }

    func removeTab(_ tabID: UUID) {
        tabs.removeAll { $0.id == tabID }
        if activeTabID == tabID {
            activeTabID = tabs.last?.id
        }
    }
}
