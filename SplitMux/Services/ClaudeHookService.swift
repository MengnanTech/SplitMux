import Foundation
import SwiftUI

/// Monitors Claude Code hook status files for tab state changes
@MainActor
@Observable
final class ClaudeHookService {
    static let shared = ClaudeHookService()

    private let statusDir = "/tmp/splitmux"
    private var monitors: [UUID: DispatchSourceFileSystemObject] = [:]
    private var dirMonitor: DispatchSourceFileSystemObject?
    private var pollTimers: [UUID: Timer] = [:]

    // MARK: - Agent Orchestration

    /// Tracked agent info across all tabs
    var agentInfos: [AgentInfo] = []

    /// Recent agent notifications (capped at 50)
    var recentNotifications: [AgentNotification] = []

    /// Summary counts
    var runningCount: Int { agentInfos.filter { $0.status == .running }.count }
    var needsInputCount: Int { agentInfos.filter { $0.status == .needsInput }.count }
    var idleCount: Int { agentInfos.filter { $0.status == .idle }.count }


    private init() {
        // Clean up all old status files on startup
        if let files = try? FileManager.default.contentsOfDirectory(atPath: statusDir) {
            for file in files {
                try? FileManager.default.removeItem(atPath: "\(statusDir)/\(file)")
            }
        }
        try? FileManager.default.createDirectory(
            atPath: statusDir,
            withIntermediateDirectories: true
        )
    }

    /// Start monitoring a tab's status file.
    /// If already monitoring (e.g. view recreated by SwiftUI during split),
    /// preserve existing state to avoid losing Claude detection status.
    func startMonitoring(tabID: UUID, onStatusChange: @escaping @MainActor (ClaudeStatus?) -> Void) {
        let path = "\(statusDir)/\(tabID.uuidString)"
        let alreadyMonitoring = pollTimers[tabID] != nil

        // Invalidate any existing timer (prevents duplicate timers on view recreation)
        pollTimers[tabID]?.invalidate()
        pollTimers.removeValue(forKey: tabID)

        if alreadyMonitoring {
            // View was recreated (e.g. split mode change) — keep existing status file
            // and agent info, just restart the timer
        } else {
            // Fresh start — reset status file and agent info
            FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
            lastStatus.removeValue(forKey: path)
            agentInfos.removeAll { $0.tabID == tabID }
        }

        // Poll-based monitoring (reliable across all scenarios)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.checkStatusFile(path: path, tabID: tabID, callback: onStatusChange)
            }
        }
        pollTimers[tabID] = timer
    }

    /// Stop monitoring a tab
    func stopMonitoring(tabID: UUID) {
        pollTimers[tabID]?.invalidate()
        pollTimers.removeValue(forKey: tabID)

        let path = "\(statusDir)/\(tabID.uuidString)"
        try? FileManager.default.removeItem(atPath: path)
        lastStatus.removeValue(forKey: path)

        // Remove from agent tracking
        agentInfos.removeAll { $0.tabID == tabID }
    }

    private var lastStatus: [String: String] = [:]

    private func checkStatusFile(path: String, tabID: UUID, callback: @escaping (ClaudeStatus?) -> Void) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            // File gone or empty — Claude has exited, clear status
            if lastStatus[path] != nil {
                lastStatus.removeValue(forKey: path)
                agentInfos.removeAll { $0.tabID == tabID }
                callback(nil)
            }
            return
        }

        // Only fire callback on actual changes
        if lastStatus[path] != content {
            lastStatus[path] = content
            let status = ClaudeStatus(rawValue: content) ?? .unknown
            callback(status)
            updateAgentInfo(tabID: tabID, status: status)
        }
    }

    // MARK: - Agent Tracking

    private func updateAgentInfo(tabID: UUID, status: ClaudeStatus) {
        if let index = agentInfos.firstIndex(where: { $0.tabID == tabID }) {
            let prev = agentInfos[index].status
            agentInfos[index].status = status
            agentInfos[index].lastStatusChange = Date()

            // Log notification on meaningful transitions
            if prev != status {
                addNotification(tabID: tabID, from: prev, to: status)
            }
        } else {
            // First status for this tab — add it
            let info = AgentInfo(tabID: tabID, status: status, lastStatusChange: Date())
            agentInfos.append(info)

            if status != .unknown {
                addNotification(tabID: tabID, from: nil, to: status)
            }
        }
    }

    /// Refresh agent infos with session/tab metadata from AppState
    func refreshAgentMetadata(from appState: AppState) {
        for i in agentInfos.indices {
            let tabID = agentInfos[i].tabID
            for session in appState.sessions {
                if let tab = session.tabs.first(where: { $0.id == tabID }) {
                    agentInfos[i].sessionName = session.name
                    agentInfos[i].tabTitle = tab.title
                    agentInfos[i].sessionID = session.id
                    break
                }
            }
        }
    }

    private func addNotification(tabID: UUID, from: ClaudeStatus?, to: ClaudeStatus) {
        let message: String
        if let from {
            message = "\(from.label) → \(to.label)"
        } else {
            message = "Agent started: \(to.label)"
        }

        let notification = AgentNotification(
            id: UUID(),
            tabID: tabID,
            status: to,
            message: message,
            timestamp: Date()
        )
        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 50 {
            recentNotifications.removeLast()
        }
    }

    /// Clean up all monitors and reset agent state
    func cleanup() {
        let ids = Array(pollTimers.keys)
        for id in ids {
            stopMonitoring(tabID: id)
        }
        agentInfos.removeAll()
        recentNotifications.removeAll()
        lastStatus.removeAll()
    }
}

// MARK: - Agent Info

struct AgentInfo: Identifiable {
    let tabID: UUID
    var status: ClaudeStatus
    var sessionName: String = ""
    var tabTitle: String = ""
    var sessionID: UUID?
    var lastStatusChange: Date

    var id: UUID { tabID }

    var duration: TimeInterval {
        Date().timeIntervalSince(lastStatusChange)
    }

    var durationString: String {
        let s = Int(duration)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s / 60) % 60)m"
    }
}

// MARK: - Agent Notification

struct AgentNotification: Identifiable {
    let id: UUID
    let tabID: UUID
    let status: ClaudeStatus
    let message: String
    let timestamp: Date
}

// MARK: - Claude Status

enum ClaudeStatus: String {
    case running
    case idle
    case needsInput = "needs-input"
    case unknown

    var icon: String {
        switch self {
        case .running: return "bolt.fill"
        case .idle: return "pause.circle.fill"
        case .needsInput: return "bell.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .needsInput: return "Needs Input"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: return .blue
        case .idle: return Color(white: 0.45)
        case .needsInput: return .orange
        case .unknown: return Color(white: 0.35)
        }
    }
}
