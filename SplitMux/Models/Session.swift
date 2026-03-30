import Foundation
import SwiftUI

/// Shared drag state for tab drag-to-reorder / drag-to-split
struct TabDragState {
    var tabID: UUID
    /// Finger position in tabContentRoot coordinate space
    var location: CGPoint
    var translation: CGSize
    var isDraggingToSplit: Bool
    var splitDirection: SplitDirection
}

@MainActor
@Observable
class Session: Identifiable, Hashable {
    /// Callback to notify AppState of changes that need saving
    var onChanged: (() -> Void)?
    let id: UUID
    var customName: String?
    var icon: String
    var tabs: [Tab]
    var activeTabID: UUID?
    var createdAt: Date
    var workingDirectory: String

    /// Optional split pane layout; nil means single-tab (no split)
    var splitRoot: SplitNode?

    /// Zoomed tab ID — when set, this pane fills the entire split area (like tmux zoom)
    var zoomedTabID: UUID?

    /// Tab drag state — shared between TabBarView (gesture) and TabContentView (floating overlay)
    var tabDragState: TabDragState?

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

    nonisolated static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
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

    /// Tabs that have Claude Code running (with their status)
    var claudeTabs: [(tab: Tab, status: ClaudeStatus)] {
        tabs.compactMap { tab in
            guard let status = tab.claudeStatus else { return nil }
            return (tab: tab, status: status)
        }
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

    /// Next sequential tab number for default naming
    var nextTabNumber: Int {
        let existingNumbers = tabs.compactMap { tab -> Int? in
            // Match "zsh", "zsh 2", "zsh 3", etc.
            if tab.title == "zsh" { return 1 }
            guard tab.title.hasPrefix("zsh "),
                  let num = Int(tab.title.dropFirst(4)) else { return nil }
            return num
        }
        return (existingNumbers.max() ?? 0) + 1
    }

    /// Create a new terminal tab with auto-incrementing name
    func createTab() -> Tab {
        let n = nextTabNumber
        let title = n == 1 ? "zsh" : "zsh \(n)"
        return Tab(title: title, icon: "terminal", content: .terminal)
    }

    func addTab(_ tab: Tab) {
        tabs.append(tab)
        activeTabID = tab.id
        onChanged?()
    }

    func removeTab(_ tabID: UUID) {
        // Clean up SSH host state
        if let tab = tabs.first(where: { $0.id == tabID }),
           case .sshTerminal(let hostID) = tab.content {
            SSHManagerService.shared.host(for: hostID)?.connectionState = .disconnected
            SSHManagerService.shared.host(for: hostID)?.connectedTabID = nil
        }

        // Clean up terminal history
        TerminalHistoryService.shared.removeHistory(for: tabID)

        // Clean up Claude hook monitoring
        ClaudeHookService.shared.stopMonitoring(tabID: tabID)

        // Determine next active tab before removing (pick adjacent tab)
        var nextActiveTabID: UUID?
        if activeTabID == tabID {
            if let splitRoot, let siblingID = splitRoot.siblingTabID(of: tabID) {
                // Split mode: pick the sibling pane in the same split
                nextActiveTabID = siblingID
            } else if let idx = tabs.firstIndex(where: { $0.id == tabID }) {
                // Tab bar: pick the tab to the left, or the right if leftmost
                if idx > 0 {
                    nextActiveTabID = tabs[idx - 1].id
                } else if idx + 1 < tabs.count {
                    nextActiveTabID = tabs[idx + 1].id
                }
            }
        }

        tabs.removeAll { $0.id == tabID }
        // Also remove from split layout
        if let root = splitRoot {
            splitRoot = root.removing(tabID: tabID)
        }
        if activeTabID == tabID {
            activeTabID = nextActiveTabID ?? tabs.last?.id
        }
        onChanged?()
    }

    // MARK: - Split Pane

    /// Enter split mode: split the active tab in the given direction
    func splitActiveTab(direction: SplitDirection) {
        guard let activeID = activeTabID else { return }
        let newTab = createTab()

        // Insert new tab right after active tab in the tab bar (not at the end)
        if let idx = tabs.firstIndex(where: { $0.id == activeID }) {
            tabs.insert(newTab, at: idx + 1)
        } else {
            tabs.append(newTab)
        }

        if let root = splitRoot, root.tabIDs.contains(activeID) {
            // Active tab is in the existing split tree — insert within it
            splitRoot = root.insertSplit(at: activeID, newTabID: newTab.id, direction: direction)
        } else {
            // No split yet, or active tab is outside the current split tree — create fresh split
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
        zoomedTabID = nil
    }

    /// Toggle zoom on the active pane (like tmux Cmd+Z)
    func toggleZoom() {
        guard splitRoot != nil, let activeID = activeTabID else { return }
        if zoomedTabID != nil {
            zoomedTabID = nil
        } else {
            zoomedTabID = activeID
        }
    }

    // MARK: - Git Branch

    /// Start polling git branch for this session's working directory
    func startGitBranchPolling() {
        refreshGitBranch()
        gitBranchTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshGitBranch()
            }
        }
    }

    func stopGitBranchPolling() {
        gitBranchTimer?.invalidate()
        gitBranchTimer = nil
    }

    private func refreshGitBranch() {
        let dir = workingDirectory
        Task { [weak self] in
            let result = await Task.detached {
                Session.fetchGitBranch(in: dir)
            }.value
            self?.gitBranch = result
        }
    }

    private nonisolated static func fetchGitBranch(in dir: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        task.currentDirectoryURL = URL(fileURLWithPath: dir)
        task.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (task.terminationStatus == 0 && !(branch?.isEmpty ?? true)) ? branch : nil
        } catch {
            return nil
        }
    }
}
