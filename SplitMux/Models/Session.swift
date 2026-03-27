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

    /// Optional split pane layout; nil means single-tab (no split)
    var splitRoot: SplitNode?

    /// Current git branch name (nil if not a git repo)
    var gitBranch: String?
    private var gitBranchTimer: Timer?

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

    init(id: UUID = UUID(), name: String? = nil, icon: String = "terminal", tabs: [Tab] = [], workingDirectory: String? = nil) {
        self.id = id
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
        // Also remove from split layout
        if let root = splitRoot {
            splitRoot = root.removing(tabID: tabID)
        }
        if activeTabID == tabID {
            activeTabID = tabs.last?.id
        }
    }

    // MARK: - Split Pane

    /// Enter split mode: split the active tab in the given direction
    func splitActiveTab(direction: SplitDirection) {
        guard let activeID = activeTabID else { return }
        let newTab = Tab(title: "zsh", icon: "terminal", content: .terminal)
        tabs.append(newTab)

        if let root = splitRoot {
            splitRoot = root.insertSplit(at: activeID, newTabID: newTab.id, direction: direction)
        } else {
            // First split — create root from active tab
            let existing = SplitNode.tab(activeID)
            let new = SplitNode.tab(newTab.id)
            switch direction {
            case .right: splitRoot = .horizontal(existing, new, ratio: 0.5)
            case .left: splitRoot = .horizontal(new, existing, ratio: 0.5)
            case .down: splitRoot = .vertical(existing, new, ratio: 0.5)
            case .up: splitRoot = .vertical(new, existing, ratio: 0.5)
            }
        }

        activeTabID = newTab.id
    }

    /// Exit split mode: collapse to single active tab
    func unsplit() {
        splitRoot = nil
    }

    // MARK: - Git Branch

    /// Start polling git branch for this session's working directory
    func startGitBranchPolling() {
        refreshGitBranch()
        gitBranchTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshGitBranch()
        }
    }

    func stopGitBranchPolling() {
        gitBranchTimer?.invalidate()
        gitBranchTimer = nil
    }

    private func refreshGitBranch() {
        let dir = workingDirectory
        Task.detached { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            task.currentDirectoryURL = URL(fileURLWithPath: dir)
            task.standardError = FileHandle.nullDevice

            let pipe = Pipe()
            task.standardOutput = pipe

            var result: String?
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result = (task.terminationStatus == 0 && !(branch?.isEmpty ?? true)) ? branch : nil
            } catch {
                result = nil
            }

            await MainActor.run {
                self?.gitBranch = result
            }
        }
    }
}
